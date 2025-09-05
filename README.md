# Business Central Extension - Pipeline Performance Comparison

This repository demonstrates a proof of concept for compiling and testing Business Central Extensions on Linux versus Windows, with a focus on measuring and comparing build pipeline performance.

## 🎯 Project Goals

- **Compare build performance** between Windows and Linux runners in CI/CD pipelines
- **Demonstrate Linux viability** for Business Central AL development 
- **Measure performance improvements** especially in build pipeline scenarios
- **Provide a comprehensive sample** AL extension for testing purposes

## 📦 Sample Extension Overview

The sample extension (`PipelinePerformanceComparison`) includes:

### Tables
- **Sample Data** (`Table 50000`) - Main data table with various field types
- **Sample Data Line** (`Table 50001`) - Related line table demonstrating relationships
- **Sample Status Enum** (`Enum 50000`) - Status enumeration

### Pages  
- **Sample Data List** (`Page 50000`) - List page with actions for data generation
- **Sample Data Lines** (`Page 50001`) - Related lines page

### Codeunits
- **Sample Data Management** (`Codeunit 50000`) - Business logic with optimized database operations
- **Sample Data Tests** (`Codeunit 50100`) - Comprehensive test coverage

### Reports
- **Sample Data Report** (`Report 50000`) - Report with data items and request page

## 🚀 Four-Pipeline Architecture

### 1. **build-windows.yml** - Windows BC Container
- **Purpose**: Production-like validation with real BC environment
- **Runner**: `windows-2022` with full Business Central container
- **Features**: BcContainerHelper, BC Test Framework, real test execution
- **Use Case**: Complete validation before production deployment

### 2. **build-windows-compile-only.yml** - Windows Compile-Only
- **Purpose**: Fast Windows-based compilation for CI/CD
- **Runner**: `windows-2022` without container overhead  
- **Features**: Direct AL compilation, dependency management, mock testing
- **Use Case**: Windows development environments needing fast feedback

### 3. **build-linux-compile-only.yml** - Linux Compile-Only
- **Purpose**: Fastest possible compilation for CI/CD optimization
- **Runner**: `ubuntu-latest` with optimized tooling
- **Features**: Native Linux tools, high-precision timing, efficient I/O
- **Use Case**: High-frequency builds, cost optimization, speed-critical CI/CD

### 4. **compare-performance.yml** - Performance Analysis
- **Purpose**: Multi-dimensional performance comparison
- **Analyzes**: All 3 build pipelines simultaneously
- **Outputs**: Markdown reports + comprehensive JSON data for external analysis

## 📊 Performance Metrics & Data Export

### Granular Performance Measurements

Each pipeline captures **detailed stage-by-stage timings**:

**Windows BC Container Pipeline:**
- AL/BcContainerHelper installation, container creation, compilation & publishing, real test execution

**Windows Compile-Only Pipeline:**
- .NET setup, AL installation/verification, system/base app download/extract, compilation, mock testing

**Linux Compile-Only Pipeline:**  
- .NET setup, AL installation/verification, system/base app download/extract, compilation, mock testing
- **Higher precision**: Nanosecond-level timing vs Windows millisecond timing

### JSON Data Export for External Analysis

Each build generates **comprehensive JSON artifacts**:

```json
{
  "platform": "linux-compile-only",
  "total_duration": 45.67,
  "measurements": [
    {"stage": "al_install", "duration": 12.34, "unit": "seconds"},
    {"stage": "compile", "duration": 15.23, "unit": "seconds"}
  ],
  "artifacts": {"app_count": 1, "total_app_size_kb": 156.7},
  "environment": {"runner_os": "Linux", "measurement_precision": "nanoseconds"}
}
```

**Perfect for**:
- Azure DevOps dashboard integration
- Power BI performance analytics  
- Custom performance monitoring tools
- Historical trend analysis

## 🛠️ Local Development

### Prerequisites
- .NET 8.0 SDK
- AL Language Extension (`dotnet tool install -g Microsoft.Dynamics.BusinessCentral.AlLanguage`)

### Build Commands
```bash
# Create package cache directory
mkdir -p .alpackages

# Compile the extension
AL compile /project:"." /packagecachepath:".alpackages" /out:"bin"

# Check AL version
AL --version
```

### Project Structure
```
├── src/
│   ├── Tables/           # AL table objects
│   ├── Pages/           # AL page objects  
│   ├── Codeunits/       # AL codeunit objects
│   ├── Reports/         # AL report objects
│   └── Test/           # AL test objects
├── .alpackages/        # Dependency packages
├── .github/workflows/  # CI/CD pipelines
└── bin/               # Compiled output
```

## 📈 Expected Performance Benefits

**Important Note**: This comparison shows different pipeline approaches:
- **Windows**: Full BC container environment with real tests (production-like)
- **Linux**: Lightweight compilation-only pipeline (CI/CD optimized)

**Linux advantages for compilation-only pipelines:**
1. **Faster startup times** - Linux runners start quicker than Windows
2. **Better I/O performance** - More efficient file system operations  
3. **Lower resource overhead** - Less system overhead during compilation
4. **Network performance** - Faster dependency downloads
5. **No container overhead** - Direct compilation vs container setup

**Windows with BC Container provides:**
1. **Real test execution** - Actual BC Test Framework runs
2. **Production-like environment** - Full BC server simulation
3. **Complete validation** - Extension deployment and testing
4. **Higher confidence** - Real-world testing scenarios

## 🔧 AL Best Practices Demonstrated

This sample follows AL development best practices from `CLAUDE.md`:

### Database Optimization
- **SetLoadFields()** usage for specific field loading
- **ReadIsolation** settings for read-only operations  
- **Primary key optimization** - PK fields automatically included

### Permission Management
- **InherentPermissions** and **InherentEntitlements** properly declared
- **Permissions** declared in codeunits (not page extensions)
- **[NonDebuggable]** attribute for sensitive procedures

### Error Handling
- **ErrorInfo** usage with rich error messages
- **Label declarations** for all error messages
- **Permission-aware navigation** actions

### Documentation
- **XML documentation** for all procedures
- **Comprehensive parameter descriptions**
- **Clear return value documentation**

## 🚦 Running the Four-Pipeline Comparison

### Quick Start
1. **Fork this repository**
2. **Enable GitHub Actions** in your fork  
3. **Trigger workflows** via push or manual dispatch
4. **Download artifacts** containing JSON performance data

### What You Get
- **3 Build Pipelines** run automatically (Windows BC, Windows Compile, Linux Compile)
- **1 Analysis Pipeline** generates comprehensive comparison reports
- **Raw JSON data** for external analysis tools (Azure DevOps, Power BI, etc.)
- **Markdown reports** with detailed performance breakdowns

### Artifacts Generated
- `windows-bc-container-artifacts/` - BC container build + test results + JSON metrics
- `windows-compile-only-artifacts/` - Compile-only build + JSON metrics  
- `linux-compile-only-artifacts/` - Linux build + JSON metrics
- `performance-analysis-complete/` - Comparison report + comprehensive JSON export

## 📋 Sample Data Generation

The extension includes functionality to generate test data:

1. Open the **Sample Data List** page
2. Run **Generate Sample Data** action  
3. Creates 100 sample records with 5 lines each
4. Use **Clear Data** to clean up test data

## 🧪 Testing

The sample includes comprehensive tests covering:
- Data generation and cleanup
- Record validation  
- Line calculation logic
- Large dataset processing
- Permission validation

Run tests using appropriate BC testing tools in your environment.

## 📊 Metrics Collection

Performance metrics are collected in JSON format:

```json
{
  "platform": "linux|windows",
  "total_duration": 45.67,
  "al_install_duration": 12.34,
  "dependency_download_duration": 8.90,
  "compile_duration": 15.23,  
  "test_duration": 9.20,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

## 🤝 Contributing

Contributions welcome! Areas for improvement:
- Additional AL object types
- More comprehensive test scenarios
- Enhanced performance measurement  
- Docker-based testing environments
- Integration with BC Test Framework

## 📄 License

This project is provided as-is for educational and comparison purposes.

---

*Built with ❤️ to demonstrate the power of Linux for Business Central AL development*