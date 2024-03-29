#!/bin/bash
# PolyCrysGen.sh: A script to generate polycrystalline samples for LAMMPS simulation.
# Utilizes ASE (Atomic Simulation Environment) and Atomsk to create unit cells,
# polycrystalline structures, and LAMMPS data files. Customizable for size,
# phase composition, and naming. All grains are randomly oriented. Assumes bulk
# structures available from ASE.build.bulk.
#
# Note: Script downloads and sets up both atomsk and python env w/ ASE.
#
# Usage:
# ./PolyCrysGen.AppImage [OPTIONS]
#
# Options:
#   -s, --size SIZE          Define the box size as "X Y Z". Default is "50 50 50".
#   -p, --phases PHASES      Specify phases and number of grains "Element1:N-Grains Element2:M-Grains".
#                            Default is "Si:2 Ge:3".
#   -x, --postfix POSTFIX    Set a postfix for the generated files. Default is "Polycrystal".
#
# Example:
# ./PolyCrysGen.sh --size "100 100 100" --phases "Si:3 Al:2" --postfix "Sample"
#
# Help:
# Pass -h or --help to display this help message.
#
# Supported Compounds:
# 	SiC
#	MgO
#	GaAs
#	ZnO
#	TiC
#	CaF2
#	NaCl
#	LiF
#	CsCl
#	PbTe
#	CdSe
#	InP
#
# (Experimental) If you would like to specify grains to be amorphous use the following syntax:
#
# ./PolyCrysGen.sh --phases "SiC-a:2 Ge:2" --size "100 100 100"
#
# This will use the script `genamorph.py` and generate a seed cell with stoichiometry
# Si:1 C:1 and then use that seed cell for two grains.
#
# Note that this can be very time-consuming because the `genmorph.py` script uses
# a min distance criteria to insert atoms via a metropolis like algo.
#
# Author: Stefan Bringuier
# Email: stefanbringuier@gmail.com
# Website: https://stefanbringuier.info
#
# References:
#
# [1] P. Hirel, Atomsk: A tool for manipulating and converting atomic data files, Computer Physics Communications 197 (2015) 212–219. https://doi.org/10.1016/j.cpc.2015.07.012.
# [2] A. Hjorth Larsen, et al., The atomic simulation environment—a Python library for working with atoms, J. Phys.: Condens. Matter 29 (2017) 273002. https://doi.org/10.1088/1361-648X/aa680e.
#
# TODO:
# - Decide on verbosity level via flag.
# - More compounds
#
###--------------
### Command line
for arg in "$@"; do
	case $arg in
	-h | --help)
		awk '/^#/{print substr($0, 3)} /^###/{exit}' "$0"
		exit 0
		;;
	esac
done

SIZE="50 50 50"
PHASES="Si:2 Ge:2"
POSTFIX="Polycrystal"

TEMP=$(getopt -o s:p:x:h --long size:,phases:,postfix:,help -n 'PolyCrysGen.sh' -- "$@")
if [ $? != 0 ]; then
	echo "Failed to parse options... exiting." >&2
	exit 1
fi

eval set -- "$TEMP"

while true; do
	case "$1" in
	-s | --size)
		SIZE="$2"
		shift 2
		;;
	-p | --phases)
		PHASES="$2"
		shift 2
		;;
	-x | --postfix)
		POSTFIX="$2"
		shift 2
		;;
	--)
		shift
		break
		;;
	*)
		echo "Internal error!"
		exit 1
		;;
	esac
done

### Parse phases and grains, and identify amorphous phases
declare -A phases_and_grains
IFS=' ' read -r -a phase_array <<<"$PHASES"
for phase in "${phase_array[@]}"; do
	if [[ $phase == *"-a:"* ]]; then
		# Amorphous phase
		echo "!! Amorphous phase(s) requested !!"
		echo "!! Will use genamorph.py to create seed !!"
		compound=$(echo $phase | sed -E 's/-a([0-9]*):/:/g' | cut -d':' -f1)
		grains=$(echo $phase | cut -d':' -f2)
		# Correctly store compound with "-a" to signify amorphous in the key
		phases_and_grains[${compound}"-a"]=$grains
	else
		# Crystalline phase
		IFS=':' read -r element grain <<<"$phase"
		phases_and_grains[$element]=$grain
	fi
done

### Remove old files
file_found=false
for pattern in *.atsk *.cfg *.txt *.xsf data.*; do
	if ls $pattern 1>/dev/null 2>&1; then
		file_found=true
		break
	fi
done

if $file_found; then
	answer="n"
	read -t 10 -p "Do you want to remove old files? (y/n): " answer || true
	if [[ $answer =~ ^[Yy](es)?$ ]]; then
		rm -f *.atsk *.cfg *.txt *.xsf data.* 2>/dev/null
	fi
fi

declare -A compounds=(
	["SiC"]="zincblende 4.3596"
	["MgO"]="rocksalt 4.212"
	["GaAs"]="zincblende 5.653"
	["ZnO"]="wurtzite 3.25 5.207"
	["TiC"]="rocksalt 4.33"
	["CaF2"]="fluorite 5.463"
	["NaCl"]="rocksalt 5.640"
	["LiF"]="rocksalt 4.02"
	["CsCl"]="cesiumchloride 4.123"
	["PbTe"]="rocksalt 6.46"
	["CdSe"]="wurtzite 4.3 7.01"
	["InP"]="zincblende 5.869"
)

# Step 1: Using ASE to create unit cells for each phase, and using genamorph.py for amorphous structures
for compound in "${!phases_and_grains[@]}"; do
	grains=${phases_and_grains[$compound]}
	if [[ $compound == *"-a" ]]; then
		# Remove the "-a" suffix to process the amorphous compound
		actual_compound=${compound%-a}
		# Extract elements and their stoichiometry for the genamorph.py script
		species_arg=""
		# Regular expression to match element symbols and stoichiometry
		regex="([A-Z][a-z]*)([0-9]*)"
		# Loop through matches in the compound string
		while [[ $actual_compound =~ $regex ]]; do
			element=${BASH_REMATCH[1]}       # Element symbol
			stoichiometry=${BASH_REMATCH[2]} # Stoichiometry (if present)
			# Append element and stoichiometry to species_arg
			if [[ ! -z $stoichiometry ]]; then
				species_arg+="$element:$stoichiometry "
			else
				species_arg+="$element:1 " # Default stoichiometry is 1
			fi
			# Remove the matched part from the compound string
			actual_compound=${actual_compound#*${BASH_REMATCH[0]}}
		done
		species_arg=$(echo $species_arg | sed 's/ $//') # Trim trailing space
		# Corrected call to genamorph.py with proper species argument formatting
		echo "!! Generating amorphous structure for $compound with species $species_arg !!"
		echo "!! This could take sometime ... !!"
		genamorph.py -s ${species_arg} -c 12 12 12 --density 1.0 -of "${compound}_unitcell.cfg" -frmt cfg
	else
		if [[ ${compounds[$compound]+_} ]]; then
			# If the element is in the compounds array, use the specified structure and lattice constant
			IFS=' ' read -r -a params <<<"${compounds[$element]}"
			crystal_structure=${params[0]}
			a=${params[1]}
			python_cmd="from ase.build import bulk; from ase.io import write; atoms = bulk('$compound', '$crystal_structure', a=$a"
			if [[ ! -z ${params[2]} ]]; then
				c=${params[2]}
				python_cmd+=", c=$c"
			fi
			python_cmd+="); write('${compound}_unitcell.cfg', atoms, format='cfg')"
			python -c "$python_cmd"
		else
			# For elements or compounds not specified in the compounds array, use the default bulk builder
			python -c "from ase.build import bulk; from ase.io import write; atoms = bulk('$compound'); write('${compound}_unitcell.cfg', atoms, format='cfg')"
		fi
	fi
done

### Create atomsk polycrystalline file
echo "box $SIZE" >polycrystal.txt
touch grain_id_list.txt
node_id=1

for element in "${!phases_and_grains[@]}"; do
	grains=${phases_and_grains[$element]}
	for ((i = 1; i <= grains; i++)); do
		let "x = RANDOM % $(echo $SIZE | cut -d' ' -f1) + 1"
		let "y = RANDOM % $(echo $SIZE | cut -d' ' -f2) + 1"
		let "z = RANDOM % $(echo $SIZE | cut -d' ' -f3) + 1"
		echo "node $x $y $z random" >>polycrystal.txt
		echo "$element $node_id" >>grain_id_list.txt
		let "node_id++"
	done
done

# Step 2: Generate images of each phase polycrystals and grains IDs
for element in "${!phases_and_grains[@]}"; do
	grains=${phases_and_grains[$element]}
	atomsk --polycrystal "${element}_unitcell.cfg" polycrystal.txt "${element}_polycrystal_0.cfg" # Start index from 0

	# Initialize the index flag to track the number of modifications
	index=0

	# Iterate through other phases to remove their grains
	for other_element in "${!phases_and_grains[@]}"; do
		if [ "$other_element" != "$element" ]; then
			ids_to_remove=$(awk -v element="$other_element" '$1 == element { ids[$2] } END { for (id in ids) { if (!min || id < min) min = id; if (!max || id > max) max = id } print min ":" max }' grain_id_list.txt)

			# Remove grains of other phases
			if [[ ! -z "$ids_to_remove" ]]; then
				atomsk "${element}_polycrystal_${index}.cfg" -select prop grainID $ids_to_remove -rmatom select "${element}_polycrystal_$((index + 1)).cfg"
				((index++)) # Increment the index for the next iteration
			else
				echo "No grain IDs found for phase $other_element to remove from $element."
			fi
		fi
	done

	# Rename the final modified file to "{element}_modified_polycrystal.cfg"
	mv "${element}_polycrystal_${index}.cfg" "${element}_modified_polycrystal.cfg"
done

# Step 3: merge all images of polycrystal phases.
selected_cfg_count=$(ls -1 *_modified_polycrystal.cfg 2>/dev/null | wc -l)

if [ "$selected_cfg_count" -eq 0 ]; then
	echo "No modified polycrystal configurations found for merging."
	exit 1
fi

atomsk --merge $selected_cfg_count *_modified_polycrystal.cfg final_${POSTFIX}.cfg

# Step 4: Convert to LAMMPS data file using ASE
python -c "
from ase.io import read, write
atoms = read('final_${POSTFIX}.cfg')
if 'grainID' in atoms.arrays:
    atoms.arrays['mol-id'] = atoms.arrays['grainID'].astype(int)
else:
    print('Warning: grainID not found in atom properties.')
write('data.${POSTFIX}', atoms, format='lammps-data', atom_style='full', masses=True, write_image_flags=True)
"

### Cleanup
file_found=false
for pattern in *.atsk *.cfg *.txt *.xsf; do
	if ls $pattern 1>/dev/null 2>&1; then
		file_found=true
		break
	fi
done

if $file_found; then
	answer="n"
	read -t 10 -p "Do you want to clean-up tmp files? (y/n): " answer || true
	if [[ $answer =~ ^[Yy](es)?$ ]]; then
		rm -f *.atsk *.cfg *.txt *.xsf 2>/dev/null
	fi
fi

echo "Polycrystalline sample in LAMMPS full style created with postfix ${POSTFIX}!"
