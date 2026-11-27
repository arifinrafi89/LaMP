"""The jobs package's router and runner shape (build plan A0.4; the loop comes in A1.3)."""
import asyncio
import inspect

from fastapi import APIRouter

from app.jobs import routes, runner


def test_tick_router_is_internal_and_out_of_the_schema():
    assert isinstance(routes.api_router, APIRouter)
    assert routes.api_router.prefix == "/internal/jobs"
    assert routes.api_router.include_in_schema is False


def test_runner_start_and_stop_are_safe_to_call_twice():
    assert inspect.iscoroutinefunction(runner.start)
    assert inspect.iscoroutinefunction(runner.stop)

    async def cycle():
        await runner.start()
        await runner.start()
        await runner.stop()
        await runner.stop()

    asyncio.run(cycle())
