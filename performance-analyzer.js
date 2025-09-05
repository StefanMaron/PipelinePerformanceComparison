const fs = require('fs');

class PerformanceAnalyzer {
    constructor() {
        this.metrics = {};
        this.rawData = {};
    }

    loadMetrics() {
        const metricFiles = [
            { key: 'windows-bc-container', path: './windows-bc-container-artifacts/windows-bc-container-metrics.json', rawPath: './windows-bc-container-artifacts/windows-bc-container-raw-measurements.json' },
            { key: 'windows-compile-only', path: './windows-compile-only-artifacts/windows-compile-only-metrics.json', rawPath: './windows-compile-only-artifacts/windows-raw-measurements.json' },
            { key: 'linux-compile-only', path: './linux-compile-only-artifacts/linux-compile-only-metrics.json', rawPath: './linux-compile-only-artifacts/linux-raw-measurements.json' }
        ];

        for (const metricFile of metricFiles) {
            try {
                if (fs.existsSync(metricFile.path)) {
                    this.metrics[metricFile.key] = JSON.parse(fs.readFileSync(metricFile.path, 'utf8'));
                }
                if (fs.existsSync(metricFile.rawPath)) {
                    this.rawData[metricFile.key] = JSON.parse(fs.readFileSync(metricFile.rawPath, 'utf8'));
                }
            } catch (error) {
                console.error(`Error loading ${metricFile.key} metrics:`, error.message);
            }
        }
    }

    formatDuration(seconds) {
        if (seconds < 1) {
            return `${(seconds * 1000).toFixed(0)}ms`;
        } else if (seconds < 60) {
            return `${seconds.toFixed(2)}s`;
        } else {
            const minutes = Math.floor(seconds / 60);
            const remainingSeconds = seconds % 60;
            return `${minutes}m ${remainingSeconds.toFixed(2)}s`;
        }
    }

    calculateImprovement(baseline, comparison) {
        if (!baseline || !comparison || baseline === 0) return 'N/A';
        const improvement = ((baseline - comparison) / baseline) * 100;
        const sign = improvement > 0 ? '+' : '';
        return `${sign}${improvement.toFixed(1)}%`;
    }

    generateCompileOnlyComparison() {
        const windowsCompile = this.metrics['windows-compile-only'];
        const linuxCompile = this.metrics['linux-compile-only'];

        if (!windowsCompile || !linuxCompile) {
            return '⚠️ Compile-only comparison data not available for both platforms.';
        }

        let report = '## 🚀 Compile-Only Performance Comparison\n\n';
        report += '| Stage | Windows | Linux | Linux Advantage |\n';
        report += '|-------|---------|-------|----------------|\n';
        
        const stages = [
            { name: '.NET Setup', windowsKey: 'dotnet_setup_duration', linuxKey: 'dotnet_setup_duration' },
            { name: 'AL Installation', windowsKey: 'al_install_duration', linuxKey: 'al_install_duration' },
            { name: 'AL Verification', windowsKey: 'al_verify_duration', linuxKey: 'al_verify_duration' },
            { name: 'Dependencies Total', windowsKey: 'total_dependency_duration', linuxKey: 'total_dependency_duration' },
            { name: 'Compilation', windowsKey: 'compile_duration', linuxKey: 'compile_duration' },
            { name: 'Mock Testing', windowsKey: 'test_duration', linuxKey: 'test_duration' },
            { name: '**Total Build Time**', windowsKey: 'total_duration', linuxKey: 'total_duration' }
        ];

        for (const stage of stages) {
            const windowsTime = windowsCompile[stage.windowsKey] || 0;
            const linuxTime = linuxCompile[stage.linuxKey] || 0;
            const improvement = this.calculateImprovement(windowsTime, linuxTime);
            
            const prefix = stage.name.startsWith('**') ? '**' : '';
            const suffix = stage.name.endsWith('**') ? '**' : '';
            const cleanName = stage.name.replace(/\*\*/g, '');
            
            report += `| ${prefix}${cleanName}${suffix} | ${prefix}${this.formatDuration(windowsTime)}${suffix} | ${prefix}${this.formatDuration(linuxTime)}${suffix} | ${prefix}${improvement}${suffix} |\n`;
        }

        const totalImprovement = ((windowsCompile.total_duration - linuxCompile.total_duration) / windowsCompile.total_duration) * 100;
        
        report += '\n### Key Insights (Compile-Only)\n\n';
        
        if (totalImprovement > 0) {
            report += `✅ **Linux is ${totalImprovement.toFixed(1)}% faster** for compile-only pipelines!\n`;
            report += `⏱️ **Time saved**: ${this.formatDuration(windowsCompile.total_duration - linuxCompile.total_duration)} per build\n\n`;
            
            // Find biggest improvement
            let maxImprovement = -Infinity;
            let bestStage = '';
            for (const stage of stages) {
                const windowsTime = windowsCompile[stage.windowsKey] || 0;
                const linuxTime = linuxCompile[stage.linuxKey] || 0;
                if (windowsTime > 0) {
                    const improvement = ((windowsTime - linuxTime) / windowsTime) * 100;
                    if (improvement > maxImprovement) {
                        maxImprovement = improvement;
                        bestStage = stage.name.replace(/\*\*/g, '');
                    }
                }
            }
            
            if (maxImprovement > 0) {
                report += `🏆 **Biggest improvement**: ${bestStage} (${maxImprovement.toFixed(1)}% faster on Linux)\n`;
            }
        } else {
            report += `⚠️ Windows is ${Math.abs(totalImprovement).toFixed(1)}% faster than Linux for compilation\n`;
        }

        return report;
    }

    generateContainerVsCompileComparison() {
        const windowsContainer = this.metrics['windows-bc-container'];
        const windowsCompile = this.metrics['windows-compile-only'];
        const linuxCompile = this.metrics['linux-compile-only'];

        if (!windowsContainer || !windowsCompile || !linuxCompile) {
            return '⚠️ Not all pipeline data available for comprehensive comparison.';
        }

        let report = '## 📊 Pipeline Strategy Comparison\n\n';
        report += '| Pipeline Type | Platform | Total Time | Testing | Use Case |\n';
        report += '|---------------|----------|------------|---------|----------|\n';
        report += `| **BC Container** | Windows | ${this.formatDuration(windowsContainer.total_duration)} | Real BC Tests | Production Validation |\n`;
        report += `| **Compile-Only** | Windows | ${this.formatDuration(windowsCompile.total_duration)} | Mock Tests | Fast CI/CD |\n`;
        report += `| **Compile-Only** | Linux | ${this.formatDuration(linuxCompile.total_duration)} | Mock Tests | **Fastest CI/CD** |\n\n`;

        const containerVsLinuxCompile = this.calculateImprovement(windowsContainer.total_duration, linuxCompile.total_duration);
        const windowsCompileVsLinuxCompile = this.calculateImprovement(windowsCompile.total_duration, linuxCompile.total_duration);
        const containerVsWindowsCompile = this.calculateImprovement(windowsContainer.total_duration, windowsCompile.total_duration);

        report += '### Speed Comparisons\n\n';
        report += `- **Linux Compile-Only vs Windows BC Container**: ${containerVsLinuxCompile} faster\n`;
        report += `- **Linux Compile-Only vs Windows Compile-Only**: ${windowsCompileVsLinuxCompile} faster\n`;
        report += `- **Windows Compile-Only vs Windows BC Container**: ${containerVsWindowsCompile} faster\n\n`;

        report += '### Pipeline Selection Guide\n\n';
        report += '**Choose Linux Compile-Only when:**\n';
        report += '- Fast feedback is critical\n';
        report += '- Compilation validation is sufficient\n';
        report += '- Running many builds per day\n';
        report += '- Cost optimization is important\n\n';
        
        report += '**Choose Windows BC Container when:**\n';
        report += '- Real BC API testing is required\n';
        report += '- Production-like validation needed\n';
        report += '- Running integration tests\n';
        report += '- Quality over speed is priority\n';

        return report;
    }

    generateDetailedStageAnalysis() {
        const windowsRaw = this.rawData['windows-compile-only'];
        const linuxRaw = this.rawData['linux-compile-only'];

        if (!windowsRaw || !linuxRaw) {
            return '⚠️ Detailed stage analysis data not available.';
        }

        let report = '## 🔍 Detailed Stage Analysis\n\n';
        report += '### Windows Build Breakdown:\n';
        
        const windowsMeasurements = windowsRaw.measurements || [];
        let windowsTotal = 0;
        for (const measurement of windowsMeasurements) {
            windowsTotal += measurement.duration;
            const percentage = windowsRaw.totals ? ((measurement.duration / windowsRaw.totals.total_duration) * 100).toFixed(1) : 'N/A';
            report += `- ${measurement.stage.replace(/_/g, ' ')}: ${this.formatDuration(measurement.duration)} (${percentage}%)\n`;
        }

        report += '\n### Linux Build Breakdown:\n';
        
        const linuxMeasurements = linuxRaw.measurements || [];
        let linuxTotal = 0;
        for (const measurement of linuxMeasurements) {
            linuxTotal += measurement.duration;
            const percentage = linuxRaw.totals ? ((measurement.duration / linuxRaw.totals.total_duration) * 100).toFixed(1) : 'N/A';
            report += `- ${measurement.stage.replace(/_/g, ' ')}: ${this.formatDuration(measurement.duration)} (${percentage}%)\n`;
        }

        return report;
    }

    generateArtifactAnalysis() {
        let report = '## 📦 Build Artifacts Analysis\n\n';
        
        const platforms = ['windows-compile-only', 'linux-compile-only'];
        const availablePlatforms = platforms.filter(p => this.metrics[p]);
        
        if (availablePlatforms.length === 0) {
            return '⚠️ No artifact data available.';
        }

        report += '| Platform | Apps Generated | Total Size | Test Files |\n';
        report += '|----------|----------------|------------|------------|\n';
        
        for (const platform of availablePlatforms) {
            const metrics = this.metrics[platform];
            const appCount = metrics.app_count || 0;
            const sizeKB = metrics.total_app_size_kb || 0;
            const testCount = metrics.test_file_count || 0;
            
            report += `| ${platform.replace('-', ' ')} | ${appCount} | ${sizeKB} KB | ${testCount} |\n`;
        }

        return report;
    }

    generateRawDataExport() {
        const exportData = {
            timestamp: new Date().toISOString(),
            metrics: this.metrics,
            rawMeasurements: this.rawData,
            summary: {
                platforms_available: Object.keys(this.metrics),
                total_builds: Object.keys(this.metrics).length
            }
        };

        fs.writeFileSync('comprehensive-performance-data.json', JSON.stringify(exportData, null, 2));
        console.log('✅ Comprehensive performance data exported to comprehensive-performance-data.json');
    }

    generateFullReport() {
        console.log('# 🚀 Comprehensive Business Central Pipeline Performance Analysis\n');
        
        const availableMetrics = Object.keys(this.metrics);
        if (availableMetrics.length === 0) {
            console.log('⚠️ No performance metrics available for analysis.');
            return;
        }

        console.log(`**Available Builds**: ${availableMetrics.join(', ')}\n`);
        
        // Generate different comparison sections
        console.log(this.generateCompileOnlyComparison());
        console.log('\n' + this.generateContainerVsCompileComparison());
        console.log('\n' + this.generateDetailedStageAnalysis());
        console.log('\n' + this.generateArtifactAnalysis());
        
        console.log('\n## 📊 Data Export\n');
        console.log('Raw performance data has been exported for external analysis (Azure DevOps, BI tools, etc.)');
        
        console.log('\n---\n');
        console.log('*Analysis generated automatically from pipeline performance measurements.*');
    }
}

// Run the analysis
const analyzer = new PerformanceAnalyzer();
analyzer.loadMetrics();
analyzer.generateFullReport();
analyzer.generateRawDataExport();