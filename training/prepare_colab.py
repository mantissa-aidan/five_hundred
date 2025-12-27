import os
import zipfile
import shutil
from datetime import datetime

def main():
    # Configuration
    PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    OUTPUT_FILENAME = "five_hundred_code.zip"
    
    # Items to include (folders/files in root)
    # We want to zip 'five_hundred' package, 'requirements.txt', 'train_agent.py'
    # And maybe 'prepare_colab.py' itself isn't needed there, but the notebooks might be useful if not uploading separately.
    # The user manual instructions said: zip the 'five_hundred' folder. 
    # But train_agent.py depends on it. Ideally we zip the WHOLE ROOT but exclude junk.
    
    INCLUDES = [
        'five_hundred',
        'training',
        'requirements.txt',
        'Train_on_Colab.ipynb'
    ]
    
    EXCLUDES = [
        '__pycache__',
        '.git',
        '.gemini',
        '.pytest_cache',
        '.DS_Store',
        'arena_history',
        'tests',
        'venv',
        'env',
        '.idea',
        '.vscode',
        '__init__.py' # if in root
    ]
    
    # Checkpoints (don't upload huge models unless requested)
    EXCLUDE_EXTS = ['.pth', '.pyc', '.zip']

    print(f"📦 Preparing package for Google Colab in: {PROJECT_ROOT}")
    
    output_path = os.path.join(PROJECT_ROOT, OUTPUT_FILENAME)
    if os.path.exists(output_path):
        os.remove(output_path)
        print("   - Removed old zip file")

    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        # Add loose files
        for item in INCLUDES:
            item_path = os.path.join(PROJECT_ROOT, item)
            
            if not os.path.exists(item_path):
                print(f"   ⚠️ Warning: {item} not found, skipping.")
                continue
                
            if os.path.isfile(item_path):
                print(f"   + Adding file: {item}")
                zipf.write(item_path, arcname=item)
            
            elif os.path.isdir(item_path):
                print(f"   + Adding folder: {item}/")
                for root, dirs, files in os.walk(item_path):
                    # Filter Excludes
                    dirs[:] = [d for d in dirs if d not in EXCLUDES]
                    
                    for file in files:
                        if any(file.endswith(ext) for ext in EXCLUDE_EXTS):
                            continue
                        if file in EXCLUDES:
                            continue
                            
                        abs_file = os.path.join(root, file)
                        rel_path = os.path.relpath(abs_file, PROJECT_ROOT)
                        zipf.write(abs_file, arcname=rel_path)

    print(f"\n✅ Success! Created '{OUTPUT_FILENAME}' ({os.path.getsize(output_path) / 1024 / 1024:.2f} MB)")
    print("\nNext Steps:")
    print("1. Open Google Drive: https://drive.google.com/")
    print(f"2. Drag and drop '{OUTPUT_FILENAME}' into your Drive root (or a folder).")
    print("3. Open your 'Train_on_Colab.ipynb' in Colab.")
    print("4. Run the notebook!")

if __name__ == "__main__":
    main()
