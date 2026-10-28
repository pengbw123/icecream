# Dataset attribution

Laurence Moroney, Rock Paper Scissors Dataset (2019).
Source: https://laurencemoroney.com/datasets.html
License: Creative Commons Attribution 2.0 (CC BY 2.0).
License text: https://creativecommons.org/licenses/by/2.0/

This project uses CGI-rendered hand images on white backgrounds for an offline
gesture-recognition prototype. It converts selected RGB pixels to RGB332,
thresholds their luminance, and trains an INT8-exported 256-24-3 neural network.
The exported sampled test vectors and model are modified/derived artifacts;
they are not the original full-resolution images. Credit for the original
dataset belongs to Laurence Moroney. No endorsement is implied.

Original archives are downloaded from the URLs used by the official TensorFlow
Datasets rock_paper_scissors builder and retained locally under ignored tmp/.
Checksums and split filenames are recorded in
src/generated/gesture/training_report.json.
