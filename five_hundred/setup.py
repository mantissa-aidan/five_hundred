from setuptools import setup, find_packages

setup(
    name='five_hundred',
    version='0.1.0',
    packages=find_packages(include=['five_hundred', 'five_hundred.*']),
    description='A Python package for the card game 500',
    long_description=open('README.md').read(),
    long_description_content_type='text/markdown',
    author='Aidan Peruch',
    author_email='your.email@example.com', # Replace with your email
    url='https://github.com/yourusername/five_hundred', # Replace with your GitHub repo URL
    classifiers=[
        'Programming Language :: Python :: 3',
        'License :: OSI Approved :: MIT License',
        'Operating System :: OS Independent',
    ],
    python_requires='>=3.6',
    install_requires=[
        # Add any dependencies here
    ],
) 