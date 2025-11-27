#!/usr/bin/env python3
"""
Simple CUDA test script
Verifies that CUDA and PyTorch are working correctly
"""

import sys
import subprocess
import os

def check_cuda():
    """Check if CUDA is available"""
    print("🔍 Checking CUDA availability...")
    
    try:
        # Check nvidia-smi
        result = subprocess.run(['nvidia-smi'], capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ NVIDIA drivers are working")
            
            # Extract GPU info
            for line in result.stdout.split('\n'):
                if 'NVIDIA' in line and 'Driver' in line:
                    print(f"   {line.strip()}")
                if 'CUDA Version' in line:
                    print(f"   {line.strip()}")
        else:
            print("❌ nvidia-smi not working")
            return False
    except Exception as e:
        print(f"❌ Error running nvidia-smi: {e}")
        return False
    
    return True

def check_python_packages():
    """Check if required Python packages are available"""
    print("\n🔍 Checking Python packages...")
    
    packages = ['torch', 'torchvision', 'numpy']
    
    for package in packages:
        try:
            if package == 'torch':
                import torch
                print(f"✅ {package}: {torch.__version__}")
                
                # Check if CUDA is available in PyTorch
                if torch.cuda.is_available():
                    print(f"   CUDA devices: {torch.cuda.device_count()}")
                    for i in range(torch.cuda.device_count()):
                        print(f"   - GPU {i}: {torch.cuda.get_device_name(i)}")
                        print(f"     Memory: {torch.cuda.get_device_properties(i).total_memory / 1024**3:.1f} GB")
                else:
                    print("   ❌ CUDA not available in PyTorch")
                    
            elif package == 'torchvision':
                import torchvision
                print(f"✅ {package}: {torchvision.__version__}")
                
            elif package == 'numpy':
                import numpy
                print(f"✅ {package}: {numpy.__version__}")
                
        except ImportError as e:
            print(f"❌ {package}: Not installed")
            print(f"   Install with: pip install {package}")
        except Exception as e:
            print(f"⚠️  {package}: Error - {e}")

def test_basic_operations():
    """Test basic tensor operations"""
    print("\n🧪 Testing basic tensor operations...")
    
    try:
        import torch
        
        # Create tensors
        a = torch.randn(3, 3)
        b = torch.randn(3, 3)
        
        # Basic operations
        c = a + b
        d = torch.matmul(a, b)
        
        print("✅ Basic CPU tensor operations work")
        
        # Test CUDA if available
        if torch.cuda.is_available():
            device = torch.device('cuda')
            a_gpu = a.to(device)
            b_gpu = b.to(device)
            c_gpu = a_gpu + b_gpu
            
            print("✅ Basic GPU tensor operations work")
            
            # Test memory transfer
            c_cpu = c_gpu.cpu()
            print("✅ GPU-CPU memory transfer works")
            
        return True
        
    except Exception as e:
        print(f"❌ Tensor operations failed: {e}")
        return False

def main():
    """Main test function"""
    print("🚀 Starting CUDA environment test")
    print("=" * 50)
    
    # Check Python version
    print(f"🐍 Python version: {sys.version}")
    
    # Run tests
    cuda_ok = check_cuda()
    check_python_packages()
    operations_ok = test_basic_operations()
    
    print("\n" + "=" * 50)
    print("📊 Test Summary:")
    
    if cuda_ok and operations_ok:
        print("🎉 All tests passed! Your CUDA environment is ready.")
        print("\nNext steps:")
        print("1. Start developing your ML/DL projects")
        print("2. Use 'cudo list' to see all environments")
        print("3. Use 'cudo run logs' to view container logs")
    else:
        print("⚠️  Some tests failed. Please check the output above.")
        sys.exit(1)

if __name__ == "__main__":
    main()