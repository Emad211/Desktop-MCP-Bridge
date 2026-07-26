from __future__ import annotations

import argparse


def main() -> None:
    parser = argparse.ArgumentParser(description="Desktop MCP Bridge")
    parser.add_argument(
        "mode",
        nargs="?",
        choices=["mcp", "actions"],
        default="mcp",
        help="Run MCP server or GPT Action HTTP gateway",
    )
    args = parser.parse_args()
    if args.mode == "actions":
        from .action_api import run_action_api

        run_action_api()
    else:
        from .server import run

        run()


if __name__ == "__main__":
    main()
