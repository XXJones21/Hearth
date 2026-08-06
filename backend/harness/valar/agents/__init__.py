"""Personas as invocable SUBAGENTS -- the Valar harness primitive.

The brain is a shared, stateless token engine; the HARNESS gives each persona
invocation its own context window, system prompt, and toolset. Any loaded
persona can invoke another persona as a subagent without a model reload (the
Fennec-as-plugin analogy: an agent invoked inside one session). This package
holds the primitive and, over time, the named agent roles built on it.
"""

from .subagent import configure_subagents, run_persona_subagent, subagents_ready

__all__ = ["configure_subagents", "run_persona_subagent", "subagents_ready"]
