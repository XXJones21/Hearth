"""Valar tool handlers.

Each module exposes one or more ``handler(args: dict) -> ToolResult`` callables
registered in ``valar/tools/tools.yaml`` via a ``"module:function"`` reference.
Handlers are standalone and unit-sane: no websocket, no session, no brain -- they
do one thing and return a ToolResult. See ``valar/tools/spec.py``.
"""
