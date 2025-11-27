# Contributing to Cudo

Thank you for your interest in contributing to Cudo! We welcome contributions from the community.

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## How to Contribute

### Reporting Bugs

1. **Check Existing Issues**: Before creating a new issue, please check if it has already been reported.
2. **Create an Issue**: Use the bug report template and provide:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (OS, Docker version, etc.)

### Suggesting Features

1. **Check Existing Issues**: See if the feature has already been suggested.
2. **Create an Issue**: Use the feature request template and provide:
   - Clear description of the feature
   - Use cases and benefits
   - Any implementation ideas

### Pull Requests

1. **Fork the Repository**
2. **Create a Feature Branch**: `git checkout -b feature/amazing-feature`
3. **Make Your Changes**
4. **Test Your Changes**: Ensure all tests pass
5. **Commit Your Changes**: Use descriptive commit messages
6. **Push to Your Fork**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

## Development Setup

### Prerequisites

- Docker
- Docker Compose
- Python 3.6+
- Bash shell

### Local Development

1. **Clone your fork**
   ```bash
   git clone https://github.com/yourusername/cudo.git
   cd cudo
   ```

2. **Test your changes**
   ```bash
   # Test syntax
   bash -n cudo
   bash -n scripts/install.sh
   
   # Test basic functionality
   ./cudo --help
   ./cudo config
   ./cudo list
   ```

3. **Run the test suite**
   ```bash
   # Run GitHub Actions locally (if available)
   act -j test
   ```

## Coding Standards

### Bash Scripts

- Use `shellcheck` to validate scripts
- Follow Google Shell Style Guide
- Use descriptive variable names
- Add comments for complex logic
- Include error handling

### Python Scripts

- Follow PEP 8 style guide
- Use type hints where appropriate
- Add docstrings for functions
- Include error handling

### Documentation

- Update README.md for new features
- Add examples for new commands
- Keep documentation up to date

## Testing

### Manual Testing

Test the following scenarios:

1. **Fresh Installation**
   ```bash
   ./scripts/install.sh local
   cudo --help
   ```

2. **Build Environment**
   ```bash
   mkdir test-project && cd test-project
   cudo build -c 11.8.0 -p 3.10
   ```

3. **Run Container**
   ```bash
   cudo run
   ```

4. **List Environments**
   ```bash
   cudo list
   cudo list --details
   cudo list --gpu
   ```

### Automated Testing

- All GitHub Actions should pass
- Shell scripts should pass `shellcheck`
- Python scripts should have valid syntax

## Release Process

1. **Version Bumping**: Update version in relevant files
2. **Changelog**: Update CHANGELOG.md with changes
3. **Testing**: Ensure all tests pass
4. **Tagging**: Create a new git tag
5. **Release**: Create GitHub release with binaries

## Getting Help

- **Issues**: Create an issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: Check the README.md first

## Recognition

Contributors will be recognized in:
- GitHub contributors list
- Release notes
- Project documentation

Thank you for contributing to Cudo! 🚀