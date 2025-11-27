"""
CUDA Environment List Tool - Simple version
Plain output like docker ps
"""

import os
import subprocess
import sys
from pathlib import Path

def get_container_status(container_name):
    """Get container status"""
    try:
        result = subprocess.run(
            ['docker', 'ps', '-a', '--format', '{{.Names}}\t{{.Status}}'],
            capture_output=True, text=True, check=True
        )
        
        for line in result.stdout.strip().split('\n'):
            if container_name in line:
                status = line.split('\t')[1]
                if status.startswith('Up'):
                    return 'running', 'Running'
                else:
                    return 'stopped', 'Stopped'
        
        return 'nonexistent', 'Not Exist'
    except subprocess.CalledProcessError:
        return 'error', 'Error'

def get_container_stats(container_name):
    """Get container resource usage"""
    try:
        # Get CPU usage
        cpu_result = subprocess.run(
            ['docker', 'stats', '--no-stream', '--format', '{{.CPUPerc}}', container_name],
            capture_output=True, text=True, check=True
        )
        cpu_usage = cpu_result.stdout.strip() if cpu_result.stdout.strip() else 'N/A'
        
        # Get memory usage - only show used memory, not total
        mem_result = subprocess.run(
            ['docker', 'stats', '--no-stream', '--format', '{{.MemUsage}}', container_name],
            capture_output=True, text=True, check=True
        )
        mem_output = mem_result.stdout.strip() if mem_result.stdout.strip() else 'N/A'
        
        # Extract only the used memory part (before the / separator)
        if mem_output != 'N/A' and '/' in mem_output:
            mem_usage = mem_output.split('/')[0].strip()
        else:
            mem_usage = mem_output
        
        return cpu_usage, mem_usage
    except subprocess.CalledProcessError:
        return 'N/A', 'N/A'

def get_gpu_memory_usage(container_name):
    """Get GPU memory usage for container"""
    try:
        # Check if container is running
        status_result = subprocess.run(
            ['docker', 'ps', '--format', '{{.Names}}'],
            capture_output=True, text=True, check=True
        )
        
        if container_name not in status_result.stdout:
            return 'N/A'
        
        # Try to get GPU memory usage using nvidia-smi inside container
        gpu_result = subprocess.run(
            ['docker', 'exec', container_name, 'nvidia-smi', '--query-gpu=memory.used', '--format=csv,noheader,nounits'],
            capture_output=True, text=True, check=True
        )
        
        if gpu_result.stdout.strip():
            gpu_memory_mb = gpu_result.stdout.strip().split('\n')[0]
            try:
                gpu_memory_gb = int(gpu_memory_mb) / 1024
                return f"{gpu_memory_gb:.1f}GB"
            except ValueError:
                return f"{gpu_memory_mb}MB"
        else:
            return 'N/A'
            
    except subprocess.CalledProcessError:
        return 'N/A'
    except Exception:
        return 'N/A'

def get_running_containers_count():
    """Get running containers count - only count cuda-project containers"""
    try:
        result = subprocess.run(
            ['docker', 'ps', '--format', '{{.Names}}'],
            capture_output=True, text=True, check=True
        )
        containers = [name for name in result.stdout.strip().split('\n') if name]
        # Only count containers that start with 'cuda-project-' and end with '-container'
        cuda_containers = [name for name in containers if name.startswith('cuda-project-') and name.endswith('-container')]
        return len(cuda_containers)
    except subprocess.CalledProcessError:
        return 0

def load_config(config_file):
    """Load config file"""
    config = {}
    try:
        with open(config_file, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    config[key] = value
        return config
    except Exception:
        return None

def shorten_path(path, max_length=80):
    """Shorten path display"""
    home = str(Path.home())
    short_path = path.replace(home, '~')
    
    if len(short_path) > max_length:
        short_path = '...' + short_path[-(max_length-3):]
    
    return short_path

def format_table(headers, data):
    """Format table with proper column widths"""
    # Calculate max width for each column
    col_widths = []
    for i in range(len(headers)):
        max_width = len(headers[i])
        for row in data:
            if i < len(row):
                max_width = max(max_width, len(str(row[i])))
        col_widths.append(max_width + 2)  # Add 2 spaces padding
    
    # Format header
    header_parts = []
    for i, header in enumerate(headers):
        header_parts.append(f"{header:<{col_widths[i]}}")
    header_line = "".join(header_parts)
    
    # Format data rows
    formatted_rows = []
    for row in data:
        row_parts = []
        for i, cell in enumerate(row):
            row_parts.append(f"{str(cell):<{col_widths[i]}}")
        formatted_rows.append("".join(row_parts))
    
    return header_line, formatted_rows

def get_system_memory():
    """Get total system memory"""
    try:
        result = subprocess.run(
            ['free', '-h'],
            capture_output=True, text=True, check=True
        )
        lines = result.stdout.strip().split('\n')
        if len(lines) >= 2:
            memory_line = lines[1].split()
            if len(memory_line) >= 2:
                return memory_line[1]  # Total memory
        return 'N/A'
    except subprocess.CalledProcessError:
        return 'N/A'

def main():
    global_config_dir = Path.home() / '.cudo-global'
    
    if not global_config_dir.exists() or not any(global_config_dir.glob('*.conf')):
        print("No CUDA environment configurations found")
        return
    
    # Parse command line arguments
    show_details = '--details' in sys.argv or '-d' in sys.argv
    show_gpu = '--gpu' in sys.argv or '-g' in sys.argv
    
    # Collect all environment information
    environments = []
    
    for config_file in global_config_dir.glob('*.conf'):
        config = load_config(config_file)
        if not config:
            continue
        
        project_name = config.get('PROJECT_NAME', 'Unknown')
        image_name = config.get('IMAGE_NAME', '')
        unique_hash = config.get('UNIQUE_HASH', '')
        # 容器名称现在基于唯一哈希
        container_name = f"cuda-project-{unique_hash}-container"
        project_path = config.get('PROJECT_PATH', 'N/A')
        config_status = config.get('STATUS', 'active')
        
        # Check if project directory still exists
        config_dir_exists = os.path.exists(os.path.join(project_path, '.cudo'))
        
        # Get container status
        status_code, status_display = get_container_status(container_name)
        
        # Format status based on config status and directory existence
        if config_status == 'deleted' or not config_dir_exists:
            formatted_status = "deleted/moved"
        else:
            formatted_status = status_display
        
        # Get resource usage (only in detailed mode)
        cpu_usage, mem_usage = get_container_stats(container_name) if show_details else ('', '')
        
        # Get GPU memory usage if requested
        gpu_memory = get_gpu_memory_usage(container_name) if show_gpu else ''
        
        # Prepare environment info
        env_info = {
            'project_name': project_name,
            'cuda_version': config.get('CUDA_VERSION', 'N/A'),
            'ubuntu_version': config.get('UBUNTU_VERSION', 'N/A'),
            'python_version': config.get('PYTHON_VERSION', 'N/A'),
            'status': formatted_status,
            'project_path': project_path,
            'cpu_usage': cpu_usage,
            'mem_usage': mem_usage,
            'gpu_memory': gpu_memory,
            'created_time': config.get('CREATED_TIME', 'N/A').strip('"'),
            'last_updated': config.get('LAST_UPDATED', 'N/A').strip('"')
        }
        
        environments.append(env_info)
    
    if not environments:
        print("No CUDA environment configurations found")
        return
    
    # Prepare table data
    if show_details or show_gpu:
        # Detailed mode
        mode_name = "Detailed"
        if show_gpu:
            mode_name += " with GPU"
        print(f"CUDA Environment List ({mode_name})")
        
        headers = ["PROJECT", "CUDA", "UBUNTU", "PYTHON", "STATUS", "CPU", "MEMORY"]
        if show_gpu:
            headers.append("GPU MEM")
        headers.append("CREATED")
        
        # Prepare data for formatting
        table_data = []
        for env in environments:
            row = [
                env['project_name'],
                env['cuda_version'],
                env['ubuntu_version'],
                env['python_version'],
                env['status'],
                env['cpu_usage'],
                env['mem_usage']
            ]
            if show_gpu:
                row.append(env['gpu_memory'])
            row.append(env['created_time'])
            
            table_data.append(row)
        
        # Format and print table
        header_line, formatted_rows = format_table(headers, table_data)
        print(header_line)
        for row in formatted_rows:
            print(row)
        
    else:
        # Simple mode
        print("CUDA Environment List")
        headers = ["PROJECT", "CUDA", "UBUNTU", "PYTHON", "STATUS", "PATH"]
        
        # Prepare data for formatting
        table_data = []
        for env in environments:
            table_data.append([
                env['project_name'],
                env['cuda_version'],
                env['ubuntu_version'],
                env['python_version'],
                env['status'],
                shorten_path(env['project_path'])
            ])
        
        # Format and print table
        header_line, formatted_rows = format_table(headers, table_data)
        print(header_line)
        for row in formatted_rows:
            print(row)
    
    # Statistics
    total_count = len(environments)
    running_count = get_running_containers_count()
    system_memory = get_system_memory()
    
    print(f"\nStatistics:")
    print(f"  Total environments: {total_count}")
    print(f"  Running: {running_count}")
    # print(f"  System memory: {system_memory}")
    # print(f"  Global config directory: {global_config_dir}")

if __name__ == '__main__':
    main()