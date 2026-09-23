# Runs the AIContextBuilder MCP server in a container.
#
# This repository holds no source code, so nothing is built here: the image
# installs the published .NET tool from nuget.org - the same package a local
# `dotnet tool install -g AIContextBuilder` gives you.
#
#   docker build -t aicb .
#   docker run --rm -i -v /path/to/your/solution:/src aicb
#
# The server speaks MCP over stdio, so `-i` is required and there is no port to
# publish. Mount the solution you want analysed and pass its path inside the
# container as the `sessionId` of any tool call - every tool accepts the
# absolute .sln / .slnx / .slnf path directly (self-init), so there is no
# separate analyze step.

# The SDK image rather than the runtime image is deliberate: analysing a
# solution needs MSBuild. The server starts and answers tools/list without it,
# so a runtime image would produce a container that looks healthy and fails at
# the first real question.
FROM mcr.microsoft.com/dotnet/sdk:8.0

# Unpinned on purpose: this image is meant to track the current release. Add
# `--version 0.5.464.36` when you need a reproducible build.
RUN dotnet tool install -g AIContextBuilder

ENV PATH="${PATH}:/root/.dotnet/tools"

WORKDIR /src

# --db-path names a container-local config database, and the path deliberately
# need not exist. Measured against 0.5.464.36: a missing file is NOT created and
# does NOT abort the start - the server prints
#   warning: --db-path not found (...); starting without a profile
# and serves the default tool pool. That is the behaviour this image wants, and
# naming the path explicitly is what keeps it deterministic: without the flag
# the server resolves the desktop app's database location instead, which does
# not exist in a container and is a path nobody has measured here.
#
# Mount a volume at /data to keep MCP profiles and insights between runs; the
# desktop app creates that database, the server alone does not.
ENTRYPOINT ["aicb", "mcp", "--db-path", "/data/aicb.acb"]
