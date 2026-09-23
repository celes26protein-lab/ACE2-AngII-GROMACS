#!/bin/bash
# =============================================================
# ACE2–Angiotensin GROMACS pipeline
# Box -> Solvation -> Ions -> EM -> NVT -> NPT -> Production MD
# =============================================================
# Requirements: GROMACS (tested with 2019.6)
#
# Usage:
#   ./run_gromacs.sh AngI     (or AngII)
#
# Expects, relative to this script:
#   topology/<COMPLEX>/topol.top   (+ its .itp files, already generated
#                                    with `gmx pdb2gmx`)
#   topology/<COMPLEX>/processed.gro  (the structure output by pdb2gmx)
#   mdp/ions.mdp, mdp/em.mdp, mdp/nvt.mdp, mdp/npt.mdp, mdp/md.mdp
# =============================================================

set -e  # stop on first error

COMPLEX=$1   # AngI or AngII
if [ -z "$COMPLEX" ]; then
  echo "Usage: ./run_gromacs.sh <AngI|AngII>"
  exit 1
fi

TOP_DIR="topology/$COMPLEX"
MDP_DIR="mdp"
OUT_DIR="run/$COMPLEX"
mkdir -p "$OUT_DIR"

cd "$OUT_DIR"

# ---- 1. Define the simulation box --------------------------------
# -c   : center the protein in the box
# -d    : minimum distance (nm) between protein and box edge
# -bt   : box type (cubic)
gmx editconf -f "../../$TOP_DIR/processed.gro" \
             -o box.gro \
             -c -d 1.0 -bt cubic

# ---- 2. Solvate the box with TIP3P water --------------------------
gmx solvate -cp box.gro \
            -cs spc216.gro \
            -p "../../$TOP_DIR/topol.top" \
            -o solvated.gro

# ---- 3. Add ions to neutralize the system --------------------------
gmx grompp -f "../../$MDP_DIR/ions.mdp" \
           -c solvated.gro \
           -p "../../$TOP_DIR/topol.top" \
           -o ions.tpr

# Replace SOL with Na+/Cl- as needed to neutralize the system
# (select the "SOL" group when prompted, typically group 13)
echo "SOL" | gmx genion -s ions.tpr \
                         -o solvated_ions.gro \
                         -p "../../$TOP_DIR/topol.top" \
                         -pname NA -nname CL -neutral

# ---- 4. Energy minimization -----------------------------------------
gmx grompp -f "../../$MDP_DIR/em.mdp" \
           -c solvated_ions.gro \
           -p "../../$TOP_DIR/topol.top" \
           -o em.tpr
gmx mdrun -deffnm em

# ---- 5. NVT equilibration (constant volume, temperature) -------------
gmx grompp -f "../../$MDP_DIR/nvt.mdp" \
           -c em.gro \
           -r em.gro \
           -p "../../$TOP_DIR/topol.top" \
           -o nvt.tpr
gmx mdrun -deffnm nvt

# ---- 6. NPT equilibration (constant pressure, temperature) -----------
gmx grompp -f "../../$MDP_DIR/npt.mdp" \
           -c nvt.gro \
           -r nvt.gro \
           -t nvt.cpt \
           -p "../../$TOP_DIR/topol.top" \
           -o npt.tpr
gmx mdrun -deffnm npt

# ---- 7. Production MD --------------------------------------------------
gmx grompp -f "../../$MDP_DIR/md.mdp" \
           -c npt.gro \
           -t npt.cpt \
           -p "../../$TOP_DIR/topol.top" \
           -o md.tpr
gmx mdrun -deffnm md

echo "Done. Production run output: $OUT_DIR/md.gro, md.xtc, md.log, md.edr"
