package main

import (
	"fmt"
	"os"
)

const EnvrcVersion = "0.1.0"

const EnvrcUsage = `ENVRC v%s - .envrc subshell loader

Usage:
  envrc shell-integration --shell (zsh|bash)
  envrc -h | --help
  envrc --version

Options:
  -h --help     Show this screen.
  --version     Show version.
`

func main() {
	args := os.Args[1:]
	envrcHelp := fmt.Sprintf(EnvrcUsage, EnvrcVersion)

	envrcBinPath, err := os.Executable()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	if len(args) == 0 {
		fmt.Print(envrcHelp)
		os.Exit(1)
	}

	switch args[0] {
	case "shell-integration":
		subArgs := args[1:]

		if len(subArgs) == 0 {
			fmt.Print(envrcHelp)
			os.Exit(1)
		}

    if subArgs[0] == "init" {
      fmt.Print(fmt.Sprintf(ZSHShellIntegration, envrcBinPath))
      os.Exit(0)
    }

		// Hook calls
		if subArgs[0] == "hook" {
			hookArgs := subArgs[1:]
			if len(hookArgs) == 0 {
				fmt.Print(envrcHelp)
				os.Exit(1)
			}
			switch hookArgs[0] {
			case "before-prompt":
				fmt.Print("echo 'before prompt'")
				os.Exit(0)
			case "before-exec":
				fmt.Print("echo 'before cmd exec'", hookArgs[1])
				os.Exit(0)
			case "on-cd":
				fmt.Print("echo 'on cd'")
				os.Exit(0)
			case "on-subshell-exit":
				fmt.Print("echo 'on subshell exit'")
				os.Exit(0)
			default:
				fmt.Print(envrcHelp)
				os.Exit(1)
			}
		}

	}

}
