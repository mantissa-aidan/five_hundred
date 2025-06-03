import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="five-hundred-card-game-engine", # Replace with your desired package name (must be unique on PyPI)
    version="0.1.0",
    author="Your Name", # Replace with your name
    author_email="your.email@example.com", # Replace with your email
    description="A Python engine for the card game Five Hundred (500).",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/yourusername/five_hundred", # Replace with your repo URL
    packages=setuptools.find_packages(where=".", include=["five_hundred*"] ,exclude=["tests*"]),
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.6",
        "Programming Language :: Python :: 3.7", # Still good to list if it runs on them
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        "Topic :: Games/Entertainment :: Card Games",
    ],
    python_requires='>=3.6',
    # install_requires=[
    #    # list your dependencies here, e.g.: 'requests>=2.20.0'
    # ],
) 