# MacTelPowerMon

**MacTelPowerMon** is a lightweight, terminal-based power and resource monitoring tool for Intel Macs. It provides realistic CPU, RAM, battery consumption estimates, and identifies applications consuming high resources, serving as a lightweight alternative to heavy apps.

---

## Features
- Displays CPU, RAM usage, and battery consumption in real time
- Estimates remaining battery life
- Highlights top processes by CPU consumption and potential energy savings
- Calculates an "ideal idle" consumption after closing the top 5 resource-hungry processes
- Lightweight, terminal-based, minimal dependencies
- Designed specifically for **Intel-based MacBooks** (tested on MacBook Pro Late 2011, 8,3 with macOS Sequoia 15.7.2)

---

## Requirements
- macOS with Intel processor
- Terminal access
- [Homebrew](https://brew.sh) for package installation
- Dependencies:
  ```bash
  brew install gawk osx-cpu-temp
  ```

> **Note:** This tool uses system utilities such as `powermetrics`, `vm_stat`, and `ioreg` which are built into macOS.

---

## Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/woss102910/MacTelPowerMon.git
   ```
2. Make the script executable:
   ```bash
   cd MacTelPowerMon
   chmod +x mac_tel_power_mon.sh
   ```
3. Run the script:
   ```bash
   ./mac_tel_power_mon.sh
   ```

---

## Usage
- The script measures power usage in multiple samples (default 5), each lasting about 7 seconds.
- Displays:
  - Current CPU and RAM usage
  - Combined power consumption (watts)
  - Top 10 processes by CPU consumption and estimated power usage
  - Estimated battery time remaining
  - Idle ideal consumption after closing the top 5 CPU-heavy processes
