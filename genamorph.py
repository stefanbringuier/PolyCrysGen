#!/usr/bin/env python3.10

"""
Create amorphous structure with given density using ASE with thread-safe updates.
Author: Stefan Bringiuer
Email: stefanbringuier@gmail.com
Website: stefanbringuier.info
Version: 1.0

NOTES: Not suitable for large simulations cells. Only constructs based on avoiding distances
less than minimum sum of covalent radii.
"""
import numpy as np
from ase import Atoms
from scipy.spatial.distance import cdist
from ase.data import covalent_radii, atomic_numbers, atomic_masses
from ase.io import write
from tqdm import tqdm
import argparse
from functools import lru_cache


@lru_cache(maxsize=None)
def get_combined_bond_length(symbol1, symbol2):
    """Estimate the combined bond length between two atoms based on their covalent radii."""
    radius1 = covalent_radii[atomic_numbers[symbol1]]
    radius2 = covalent_radii[atomic_numbers[symbol2]]
    return radius1 + radius2


def minimum_image_distance(position1, position2, cell_size):
    """Compute the minimum image distance between two points considering periodic boundary conditions."""
    delta = np.abs(position1 - position2)
    delta = np.where(delta > 0.5 * cell_size, cell_size - delta, delta)
    return np.sqrt((delta**2).sum(axis=-1))


def is_position_allowed(
    new_pos, existing_positions, symbol, atoms, cell_size, min_factor=1.1
):
    """Check if a new position is allowed based on nearest neighbor distances, considering periodic boundary conditions."""
    if not existing_positions.size:
        return True

    distances = np.array(
        [minimum_image_distance(new_pos, pos, cell_size) for pos in existing_positions]
    )
    for dist, existing_symbol in zip(distances, atoms.get_chemical_symbols()):
        min_dist_allowed = (
            get_combined_bond_length(symbol, existing_symbol) * min_factor
        )
        if dist < min_dist_allowed:
            return False
    return True


def calculate_required_atoms(atomic_symbols, cell_size, target_density):
    """Calculate the number of atoms required to achieve a target density."""
    cell_volume = np.prod(cell_size)
    mcf = 1.66053906660e-24
    total_mass_g = [
        atomic_masses[atomic_numbers[symbol]] * mcf * stoichiometry
        for symbol, stoichiometry in atomic_symbols.items()
    ]
    cell_volume_cm3 = cell_volume * 1e-24
    num_formula_units = [(target_density * cell_volume_cm3) / g for g in total_mass_g]
    total_atoms = [
        stoichiometry * num_formula_units[i]
        for i, (symbol, stoichiometry) in enumerate(atomic_symbols.items())
    ]
    required_atoms = int(np.round(sum(total_atoms)))
    return required_atoms


def select_position_metropolis(
    existing_positions,
    cell_size,
    history,
    symbol,
    atoms,
    temperature=0.1,
    max_attempts=1_000,
):
    """Select a new position using a Metropolis-like algorithm biased by distance to existing atoms."""
    if not existing_positions.size:
        return (
            np.random.rand(3) * cell_size
        )  # Return a random position if no existing positions

    best_pos = None
    max_score = -np.inf

    for _ in range(max_attempts):
        new_pos = np.random.rand(3) * (cell_size - 1) + 0.5  # Shift away from edges.
        if is_position_allowed(new_pos, existing_positions, symbol, atoms, cell_size):
            # Score based on minimum distance to existing positions, inversely proportional to distance
            distances = cdist([new_pos], existing_positions)[0]
            score = np.min(distances) / temperature
            if score > max_score:
                best_pos = new_pos
                max_score = score

    return best_pos if best_pos is not None else np.random.rand(3) * cell_size


def create_amorphous_structure(
    atomic_symbols, cell_size, target_density, max_attempts=1_000_000
):
    num_atoms = calculate_required_atoms(atomic_symbols, cell_size, target_density)

    if not np.isfinite(num_atoms):
        raise ValueError("Calculated number of atoms is not finite, check inputs.")

    if isinstance(cell_size, (float, int)):
        cell_size = np.array([cell_size, cell_size, cell_size])
    else:
        cell_size = np.array(cell_size)

    atoms = Atoms(cell=cell_size, pbc=True)
    elements, stoichiometries = zip(*atomic_symbols.items())
    stoichiometry_ratios = np.array(stoichiometries) / sum(stoichiometries)
    atom_counts = np.round(stoichiometry_ratios * num_atoms).astype(int)

    if np.any(np.isnan(atom_counts)) or np.any(atom_counts < 0):
        raise ValueError("Atom counts calculation resulted in NaN or negative values.")

    positions = []
    total_atoms = sum(atom_counts)
    pbar = tqdm(total=total_atoms, unit="atom", desc="Creating amorphous structure")

    for symbol, target_count in zip(elements, atom_counts):
        for _ in range(target_count):
            existing_positions = np.array(positions)
            new_pos = select_position_metropolis(
                existing_positions, cell_size, positions, symbol, atoms
            )

            if new_pos is not None:
                atoms += Atoms([symbol], positions=[new_pos.tolist()])
                positions.append(new_pos)
                pbar.update(1)
            else:
                print("Warning: Failed to find a suitable position for an atom.")
                break

    pbar.close()
    return atoms


def main():
    parser = argparse.ArgumentParser(
        description="Create amorphous structure with given density"
    )
    parser.add_argument(
        "-s",
        "--symbols",
        nargs="+",
        help="Atomic symbols and stoichiometry (e.g., Si:1 O:2)",
        required=True,
    )
    parser.add_argument(
        "-c",
        "--cell_size",
        nargs="+",
        type=float,
        help="Cell size along x, y, and z axes (e.g., --cell_size 10 10 10)",
        required=True,
    )
    parser.add_argument(
        "--density", type=float, help="Target density in g/cm^3", default=1.0
    )
    parser.add_argument(
        "-of", "--outfile", type=str, help="Output file name", default="amorphous.cfg"
    )
    parser.add_argument(
        "-frmt", "--file_frmt", type=str, help="Output file format", default="cfg"
    )

    args = parser.parse_args()

    atomic_symbols = {}
    for sym in args.symbols:
        symbol, stoichiometry = sym.split(":")
        atomic_symbols[symbol] = int(stoichiometry)

    amorphous_structure = create_amorphous_structure(
        atomic_symbols=atomic_symbols,
        cell_size=args.cell_size,
        target_density=args.density,
    )
    density = (
        np.sum(amorphous_structure.get_masses()) / amorphous_structure.get_volume()
    )
    print("Final density:", density, " amu/A^3")
    write(args.outfile, amorphous_structure, format=args.file_frmt)


if __name__ == "__main__":
    main()
