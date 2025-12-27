# Cloud Training Guide (Google Colab)

This guide explains how to move your training to the cloud using Google Colab's free GPU resources.

## Why Colab?
- **Free GPU**: Much faster training than typical CPUs (Mac M1/M2/M3 are fast, but NVIDIA GPUs are standard for PyTorch).
- **No Local Heat/Noise**: Save your battery and fans.
- **Persistence**: Save checkpoints directly to your Google Drive.

## Step 1: Prepare Your Code
We need to get your code into Colab. I've created a script to do the heavy lifting.

**Run this command in your terminal:**
```bash
python prepare_colab.py
```
This will create `five_hundred_code.zip` containing everything you need.

## Step 2: Use the Colab Notebook
1. Go to [Google Colab](https://colab.research.google.com/).
2. Create a **New Notebook**.
3. Go to **Runtime > Change runtime type** and select **T4 GPU** (or better if you have Pro).
4. Copy-paste the content of the notebook below (or upload the `.ipynb` file if provided).

## Colab Notebook Content (`Train_on_Colab.ipynb`)

Copy the JSON below and save it as `Train_on_Colab.ipynb`, then upload to Colab. Or simpler: copy the code blocks into a new notebook manually.

### Block 1: Setup & Connect Drive
```python
from google.colab import drive
import os

# 1. Mount Google Drive (to save models persistently)
drive.mount('/content/drive')

# Create a folder for our project
PROJECT_DIR = '/content/drive/MyDrive/FiveHundredRL'
os.makedirs(PROJECT_DIR, exist_ok=True)
print(f"Project Directory: {PROJECT_DIR}")
```

### Block 2: Upload Code (One Time)
*Run this only once to upload your zip file, or drag-and-drop your `five_hundred_code.zip` into the file explorer on the left.*

```python
import shutil

# If you dragged the zip to the runtime content:
if os.path.exists('/content/five_hundred_code.zip'):
    shutil.unpack_archive('/content/five_hundred_code.zip', '/content')
    print("Code unpacked!")
else:
    print("Please upload 'five_hundred_code.zip' to the files tab!")
```

### Block 3: Install Dependencies
```python
!pip install numpy torch
```

### Block 4: Run Training
This command runs the training and saves checkpoints to your Google Drive every 50 episodes.

```python
import sys
import os

# Add code to path
sys.path.append('/content')

# Ensure we are in the right directory
os.chdir('/content')

# Run Training!
# Checkpoints will be saved to your Drive folder.
!python five_hundred/train_agent.py --save-dir "/content/drive/MyDrive/FiveHundredRL/checkpoints"
```

## Step 3: Monitoring
The training logs will appear in the Colab cell output. You can stop execution at any time; the checkpoints in your Drive are safe.

## Step 4: Resume or Download
- **To Resume**: Point the `--save-dir` to the same Drive folder. The script auto-detects existing checkpoints.
- **To Play Locally**: Download the latest `.pth` file from your Google Drive and place it in your local `five_hundred/static/` folder (rename or configure `play_game.py` to load it).
