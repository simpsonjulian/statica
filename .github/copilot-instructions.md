# Project Overview
Statica is a tool for analyzing codebases that cannot be compiled and analyzed with the usual tools.  Typically, this applies to Java and C# apps.  The goal of statica is to surface security or quality issues and provide a console text or HTML report based on the findings.  All the tools render SARIF files that are used to:

- generate a single HTML report
- generate console output

## Distribution and dependencies
Statica is distributed using homebrew because homebrew is a convenient way to get all the dependencies.  If a dependency isn't in homebrew, rubygems or python, statica can't use it.

## Supported platforms
Statica supports macOS and Linux.
It may work on Cygwin or WSL, but that is not supported at present.

## Project structure
- `./tools.d` is where the plugins live
- `spec` is where the RSpec tests live
- `/`is where the statica core bash and ruby files live

## Coding standards
- indent with 2 spaces, never use tabs
- use bash and ruby idioms and commonly accepted standards
- Keep CLI interface simple and intuitive
- Prioritize ease of installation and updates (Homebrew compatibility)
- All security tool outputs should be converted to SARIF format
- Maintain sequential execution of tools for predictable behavior
- Generate both HTML and console output formats
- 
## Key Principles
- **Dogfooding**: Statica should be able to analyze its own codebase
- **Security**: As a security tool statica should not reduce the user's security posture
- **Simplicity**: Make it easy to run all tools with a single command
- **Unified reporting**: Merge all tool results into one cohesive view
- **Cross-platform**: Support macOS and Linux via Homebrew
- **Extensibility**: Design for easy addition of new security tools
- **Performance**: Run tools efficiently in sequence


## When adding new features
- Ensure new security tools output to SARIF format
- Maintain backward compatibility with existing command structure
- Update HTML report generation to include new tool results
- Add clear documentation for any new tools or options