# PolyCrysGen

**Author:**
Stefan Bringuier

**Email:**
stefanbringuier@gmail.com

**Website:**
[https://stefanbringuier.info](https://stefanbringuier.info)

**Description:**
A script to generate polycrystalline samples for LAMMPS simulation. Utilizes ASE (Atomic Simulation Environment) and Atomsk to create unit cells, polycrystalline structures, and LAMMPS data files. Customizable for size, phase composition, and naming. All grains are randomly oriented. Assumes bulk structures available from ASE.build.bulk. You should be able to create as many elemental phases+grains as needed.

> Note: Assumes the structures that are available in ASE.build.bulk function all.

## Usage
If you have python with [ASE](https://wiki.fysik.dtu.dk/ase/) and your linux environment path includes the [`atomsk`](https://atomsk.univ-lille.fr/) binary then the [PolyCrysGen.sh](./PolyCrysGen.sh) file can be ran as is either with `bash PolyCrysGen.sh` or with `chmod +x PolyCrysGen.sh`.

Otherwise you can use the [AppImage](https://appimage.org/) release by downloading and then in the terminal:

```shell
chmod +x PolyCrysGen.AppImage
./PolyCrysGen.AppImage --help
```

**Options:**
- `-s, --size SIZE`: Define the box size as "X Y Z". Default is "50 50 50".
- `-p, --phases PHASES`: Specify phases and number of grains "Element1:N-Grains Element2:M-Grains". Default is "Si:2 Ge:3".
- `-x, --postfix POSTFIX`: Set a postfix for the generated files. Default is "Polycrystal".

**Example:**
`./PolyCrysGen.AppImage --size "120 120 120" --phases "Si:3 Ge:2 C:3 " --postfix "SiGeC_Polycrystal"`


# References
- [1] P. Hirel, Atomsk: A tool for manipulating and converting atomic data files, Computer Physics Communications 197 (2015) 212–219. [https://doi.org/10.1016/j.cpc.2015.07.012](https://doi.org/10.1016/j.cpc.2015.07.012).
- [2] A. Hjorth Larsen, et al., The atomic simulation environment—a Python library for working with atoms, J. Phys.: Condens. Matter 29 (2017) 273002. [https://doi.org/10.1088/1361-648X/aa680e](https://doi.org/10.1088/1361-648X/aa680e).

