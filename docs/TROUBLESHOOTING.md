# Troubleshooting Guide

Common issues and solutions.

## Permission Denied Errors

**What you're seeing:**

```
(permission denied)
Warning: Cannot read I/O stats (requires root)
```

Or incomplete output with missing sections.


**Why it happens:**

Linux protects process information. You can only see full details for:
- Processes you own
- All processes if you're root

This is a security feature, not a bug.

**The fix:**

Run with `sudo`:

```bash
# Full access to all process information
sudo s9-inspect 1234
sudo s9-fdmap --leaks
sudo s9-anomaly
```

**Still seeing issues?**

Some systems have additional restrictions (SELinux, AppArmor, container isolation). Check your security policies if `sudo` doesn't help.

## "Command not found" Errors

**What you're seeing:**

```bash
s9-inspect: command not found
```

**Why it happens:**

The Substrata9 tools aren't in your shell's PATH.


**The fix (pick one):**

```bash
# Option 1: Use the full path
./bin/s9-inspect 1234

# Option 2: Add to PATH for this session
export PATH="$PATH:$(pwd)/bin"
s9-inspect 1234

# Option 3: Add to PATH permanently (add to ~/.bashrc)
echo 'export PATH="$PATH:/path/to/Substrata9/bin"' >> ~/.bashrc
source ~/.bashrc

# Option 4: Install system-wide
sudo make install
```
## Missing Dependencies

**What you're seeing:**

```
Error: bc is required but not installed
```


**Why it happens:**

Substrata9 needs a few standard utilities. Most are pre-installed, but `bc` sometimes isn't.


**The fix:**

```bash
# Debian/Ubuntu
sudo apt install bc

# RHEL/CentOS/Fedora
sudo dnf install bc

# Alpine
apk add bc
```

**Other missing tools?**

If you see errors about `awk`, `sed`, or `grep`, something is very wrong with your system — these are part of the base install on virtually all Linux distributions.

## "Process not found" Errors

**What you're seeing:**

```
Warning: Process 12345 does not exist
Warning: No process found matching 'myapp'
```

**Why it happens:**

Processes are transient. The process might have:
- Exited between when you typed the command and when it ran
- A different name than you expected
- Multiple instances (you'll need to pick one)


**The fix:**

```bash
# Use pgrep to find the current PID
s9-inspect $(pgrep -n nginx)  # -n = newest matching process

# Or just use the name — the tool will find it
s9-inspect nginx

# If there are multiple matches, you'll be prompted
s9-inspect python
# → "Multiple processes found matching 'python': 1234, 5678, 9012"
# → Pick the specific PID you want
```

## Weird Characters in Output

**What you're seeing:**

```
\033[0;31mError:\033[0m Something went wrong
```

Instead of colored text.


**Why it happens:**

Your terminal doesn't support ANSI color codes, or you're piping output somewhere that doesn't handle them.


**The fix:**

```bash
# Disable colors entirely
NO_COLOR=1 s9-inspect 1234

# Or if piping to a pager, tell it to handle colors
s9-tree | less -R
```

**Using an older terminal?**

Substrata9 detects "dumb" terminals and disables colors automatically. If detection isn't working, set `TERM=dumb` or `NO_COLOR=1`.

## JSON Output Issues

**What you're seeing:**

- Empty JSON: `{}`
- Invalid JSON that `jq` can't parse
- Missing fields


**Why it happens:**

- The process exited during inspection
- Permission denied for some data
- The process is in an unusual state


**The fix:**

```bash
# Validate the JSON first
s9-inspect 1234 --json | jq .

# If it's empty, check if the process exists
ls -la /proc/1234

# Run with sudo for complete data
sudo s9-inspect 1234 --json | jq .
```

**Parsing errors?**

If you're getting JSON parse errors, please [open an issue](https://github.com/iamrahulreddy/Substrata9/issues) — that's a bug that should be fixed.

## 🐧 WSL-Specific Issues

Running on Windows Subsystem for Linux? Here are some quirks you might hit.


### Scripts Open in Editor Instead of Running

**What you're seeing:**

Running `./bin/s9-inspect` opens the file in VS Code or Notepad instead of executing it.


**Why it happens:**

Windows has file associations for `.sh` files, and you're running from PowerShell or CMD.


**The fix:**

```powershell
# Run explicitly with bash
bash ./bin/s9-inspect 1234

# Or from within WSL
wsl ./bin/s9-inspect 1234
```


### Network/Socket Errors

**What you're seeing:**

```
Handshake failed
Connection refused
```


**Why it happens:**

WSL's networking stack can be finicky, especially WSL1.


**The fix:**

- These are often transient — try again
- Make sure WSL is up to date: `wsl --update`
- If persistent, try WSL2 which has better Linux compatibility

## Scripts Not Executable

**What you're seeing:**

```bash
bash: ./bin/s9-inspect: Permission denied
```


**Why it happens:**

The execute bit isn't set on the script files.


**The fix:**

```bash
chmod +x bin/*
chmod +x examples/*
chmod +x lib/*
```

**Cloned on Windows?**

Git on Windows sometimes doesn't preserve execute permissions. The `chmod` fix above will sort it out.

## Slow Performance

**What you're seeing:**

Tools taking a long time to run, especially `s9-tree` or `s9-fdmap`.


**Why it happens:**

- Scanning thousands of processes takes time
- Each process requires multiple file reads from `/proc`
- Shell scripts are slower than compiled languages


**The fix:**

```bash
# Limit the scope
s9-tree --depth 3              # Don't go too deep
s9-tree --user www-data        # Filter to specific user
s9-fdmap --top 20              # Only show top 20

# For s9-anomaly, run specific checks
s9-anomaly --zombies           # Just zombies, not full scan
```

**Need faster?**

For high-frequency monitoring, consider compiled tools like `htop`, `atop`, or eBPF-based solutions. Substrata9 is optimized for interactive diagnostic work, not continuous monitoring.

## Zombie Processes Won't Go Away

**What you're seeing:**

`s9-anomaly --zombies` keeps finding the same zombies.


**Why it happens:**

Zombies exist because their parent process hasn't called `wait()` to reap them. The zombie will persist until:
- The parent reaps it
- The parent exits (then init adopts and reaps the zombie)


**The fix:**

You can't kill a zombie directly (it's already dead). Your options:

```bash
# Find the parent that's not reaping
s9-anomaly --zombies
# → Shows parent PID and name

# Option 1: Fix the parent (if it's your code)
# Add proper wait() calls for child processes

# Option 2: Restart the parent
sudo systemctl restart <service>

# Option 3: Kill the parent (zombies get adopted by init and reaped)
sudo kill <parent_pid>
```

## Still Stuck?

If none of the above helps:

1. **Check the version:**
   ```bash
   s9-inspect --version
   ```

2. **Run with debug output:**
   ```bash
   S9_DEBUG=1 s9-inspect 1234
   ```

3. **Open an issue** with:
   - The exact command you ran
   - The full error output
   - Your OS and kernel version (`uname -a`)
   - Bash version (`bash --version`)

[Open an issue on GitHub](https://github.com/iamrahulreddy/Substrata9/issues)

## See Also

- [Usage Guide](USAGE.md) — Detailed usage for all tools
- [Architecture](ARCHITECTURE.md) — How Substrata9 works internally
- [Contributing](../CONTRIBUTING.md) — To contribute!

*Part of Substrata9 — Linux Process Archaeology Toolkit*
