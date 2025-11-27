# Basic CUDA Project Example

This is a basic example project demonstrating how to use `cudo` to set up a CUDA development environment.

## Quick Start

1. **Navigate to this directory**
   ```bash
   cd examples/basic-cuda-project
   ```

2. **Build the CUDA environment**
   ```bash
   ../../cudo build -c 11.8.0 -p 3.10
   ```

3. **Run and enter the container**
   ```bash
   ../../cudo run
   ```

4. **Test CUDA installation (inside container)**
   ```bash
   python test_cuda.py
   nvidia-smi
   ```

## Project Structure

```
basic-cuda-project/
├── README.md          # This file
├── test_cuda.py       # Simple CUDA test script
└── requirements.txt   # Python dependencies
```

## What's Included

- **CUDA 11.8.0** with Python 3.10
- **Miniconda** environment
- **Common ML libraries**: PyTorch, TensorFlow, etc.
- **Development tools**: git, vim, tmux, curl

## Test Script

The `test_cuda.py` script verifies that:
- CUDA is available
- PyTorch can access GPU
- Basic tensor operations work

## Customization

You can customize the environment by modifying the build command:

```bash
# Different CUDA version
cudo build -c 12.4.0 -p 3.11

# With CUDA Toolkit
cudo build -t true

# Custom image name
cudo build -i my-custom-image
```

## Next Steps

1. Add your own code to the project
2. Install additional packages with `pip install`
3. Use `cudo list` to see all your environments
4. Use `cudo run logs` to view container logs