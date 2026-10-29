# Temporal narrative hypergraphs of climate news (COP26–COP28)

Code, data and results of the paper.

## Run

Python 3.10+:

    pip install -r requirements.txt
    python src/3_mine.py
    python src/4_sensitivity.py
    python src/5_figures.py
    python src/6_hypergraph_pdf.py

Results are written to `results/` (already included). Steps 3–6 start from `data/transactions/`.

To rebuild the data from GDELT first (several hours):

    python src/1_download.py
    python src/2_build_transactions.py --replace

## Viewer

`viewer/HyperGodot.exe` (Windows) shows the `.txt` hypergraphs in its folder.
On other systems open `viewer/source/project.godot` with Godot 4.4.

## Font

The published figures use Times New Roman, which cannot be redistributed; the bundled
Liberation Serif is used instead. For identical figures, place your own `Times New Roman.ttf`
in `fonts/` and next to `viewer/HyperGodot.exe`.

## Licence

Code: MIT. Data and results: CC BY 4.0. GDELT data: cite the GDELT Project.