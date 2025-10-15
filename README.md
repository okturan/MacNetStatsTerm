    __  __            _   _      _   ____  _        _       _____
   |  \/  | __ _  ___| \ | | ___| |_/ ___|| |_ __ _| |_ ___|_   _|__ _ __ _ __ ___
   | |\/| |/ _` |/ __|  \| |/ _ \ __\___ \| __/ _` | __/ __|| |/ _ \ '__| '_ ` _ \
   | |  | | (_| | (__| |\  |  __/ |_ ___) | || (_| | |_\__ \| |  __/ |  | | | | | |
   |_|  |_|\__,_|\___|_| \_|\___|\__|____/ \__\__,_|\__|___/|_|\___|_|  |_| |_| |_|

Terminal network monitor for macOS. Real-time interface stats with minimal overhead.

[screenshot]

![Network Monitor](screenshot.jpg)

[requirements]

* macOS (uses netstat/route)
* bash + bc

[usage]

    $ ./netmon.sh

Auto-detects active interface. Updates every second. Scales KB/s >> MB/s automatically.
Press ^C to exit cleanly.

[what it does]

> Polls netstat byte counters at 1sec intervals
> Calculates transfer deltas (rx/tx)
> Renders to alternate screen buffer (no terminal pollution)
> Traps signals for proper cleanup

[implementation notes]

Pure bash. No external dependencies beyond standard unix tools. Uses tput for screen
control and bc for floating point math. Alternate screen buffer keeps your scrollback
clean.
