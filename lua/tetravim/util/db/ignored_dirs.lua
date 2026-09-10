-- TetraVim Spring Datasource Discovery -- directory denylist.
--
-- Carved out of lua/tetravim/util/db.lua: the ~90-line set of directory names
-- the config-file walker never descends into. Spring `application.*` config
-- never lives under any of these, so over-ignoring here only trims walk time --
-- it cannot hide a real datasource. The set mirrors what IDEs (IntelliJ
-- excluded folders, Eclipse derived resources, VS Code files.exclude) and
-- `.gitignore` conventions skip by default. Returned as a name->true lookup so
-- the walker can test membership in O(1).

local NAMES = {
  -- VCS metadata
  ".git",
  ".svn",
  ".hg",
  ".bzr",
  "CVS",
  -- JVM build output
  "target", -- Maven
  "build", -- Gradle
  "bin", -- Eclipse / Buildship
  "out", -- IntelliJ
  "classes",
  "generated",
  "generated-sources",
  ".gradle",
  ".mvn",
  -- JS/TS build output
  "dist",
  ".next",
  ".nuxt",
  ".svelte-kit",
  ".output",
  ".parcel-cache",
  ".turbo",
  "coverage",
  "storybook-static",
  -- Other-language build output
  "_build", -- Elixir / OCaml
  "zig-out",
  "obj", -- MSBuild
  "cmake-build-debug",
  "cmake-build-release",
  "Debug", -- MSBuild / CMake
  "Release",
  -- Dependency / package caches
  "node_modules",
  "bower_components",
  ".pnpm-store",
  "vendor", -- Go / PHP / Ruby
  ".venv",
  "venv",
  "env",
  ".bundle",
  ".cargo",
  "Pods", -- CocoaPods
  ".m2",
  ".ivy2",
  ".dart_tool",
  -- IDE / editor metadata
  ".idea",
  ".vscode",
  ".vs",
  ".settings", -- Eclipse
  ".metadata", -- Eclipse workspace
  ".fleet",
  ".zed",
  "nbproject", -- NetBeans
  ".history", -- Local History
  -- Tool / framework caches
  "__pycache__",
  ".mypy_cache",
  ".pytest_cache",
  ".ruff_cache",
  ".tox",
  ".nox",
  ".sass-cache",
  ".terraform",
  ".serverless",
  ".nyc_output",
  -- Project-specific: stop the walker descending Java package trees and
  -- test-resource roots (test-scoped config is not a real datasource).
  "java",
  "kotlin",
  "scala",
  "groovy",
  "test",
  ".github",
  ".ansible",
  -- OS / misc
  ".cache",
  "tmp",
  "temp",
  "logs",
  "$RECYCLE.BIN",
}

local set = {}
for _, name in ipairs(NAMES) do
  set[name] = true
end

return set
