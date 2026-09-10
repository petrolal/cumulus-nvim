-- TetraVim New-File templates -- built-in template bodies.
--
-- Carved out of lua/tetravim/util/edit/filetemplate.lua: this is the ~590-line
-- `M.builtin` catalog (one entry per built-in "New File" type, keyed
-- `<category>.<kind>`). The engine (picker, directive parsing, render,
-- scaffold) stays in the parent module, which re-exports this table as
-- `filetemplate.builtin`. Body closures only touch the substitution `ctx`
-- plus the two package-prefix helpers below.

--- `package x;\n\n` prefix (Java/Groovy) or "" when outside a source root.
local function jpkg(ctx)
  return ctx.package ~= "" and ("package " .. ctx.package .. ";\n\n") or ""
end

--- `package x\n\n` prefix (Kotlin/Scala) or "".
local function kpkg(ctx)
  return ctx.package ~= "" and ("package " .. ctx.package .. "\n\n") or ""
end

--- @type table<string, { label: string, category: string, ext: string, langs: string[], fixed_name?: string, body: fun(ctx: table): string }>
return {
  -- ---- Java ----------------------------------------------------------------
  ["java.class"] = {
    label = "Java Class",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c) .. ("public class %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["java.interface"] = {
    label = "Java Interface",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c) .. ("public interface %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["java.enum"] = {
    label = "Java Enum",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c) .. ("public enum %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["java.record"] = {
    label = "Java Record",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c) .. ("public record %s(${cursor}) {\n}\n"):format(c.name)
    end,
  },
  ["java.annotation"] = {
    label = "Java Annotation",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c)
        .. ("import java.lang.annotation.*;\n\n@Retention(RetentionPolicy.RUNTIME)\npublic @interface %s {\n    ${cursor}\n}\n"):format(
          c.name
        )
    end,
  },
  ["java.abstract"] = {
    label = "Java Abstract Class",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c) .. ("public abstract class %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["java.exception"] = {
    label = "Java Exception",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c)
        .. ("public class %s extends RuntimeException {\n\n    public %s(String message) {\n        super(message);\n    }\n\n    public %s(String message, Throwable cause) {\n        super(message, cause);\n    }\n    ${cursor}\n}\n"):format(
          c.name,
          c.name,
          c.name
        )
    end,
  },
  ["java.test"] = {
    label = "Java Test (JUnit 5)",
    category = "Java",
    ext = "java",
    langs = { "java" },
    body = function(c)
      return jpkg(c)
        .. ("import org.junit.jupiter.api.Test;\nimport static org.junit.jupiter.api.Assertions.*;\n\nclass %s {\n\n    @Test\n    void ${cursor}() {\n    }\n}\n"):format(
          c.name
        )
    end,
  },
  ["java.package-info"] = {
    label = "Java package-info.java",
    category = "Java",
    ext = "java",
    langs = { "java" },
    fixed_name = "package-info",
    body = function(c)
      local pkg = c.package ~= "" and c.package or "your.package"
      return ("/**\n * ${cursor}\n */\npackage %s;\n"):format(pkg)
    end,
  },

  -- ---- Kotlin ------------------------------------------------------------
  ["kt.class"] = {
    label = "Kotlin Class",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. ("class %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["kt.data"] = {
    label = "Kotlin Data Class",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. ("data class %s(${cursor})\n"):format(c.name)
    end,
  },
  ["kt.sealed"] = {
    label = "Kotlin Sealed Class",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. ("sealed class %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["kt.sealed-interface"] = {
    label = "Kotlin Sealed Interface",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. ("sealed interface %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["kt.interface"] = {
    label = "Kotlin Interface",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. ("interface %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["kt.enum"] = {
    label = "Kotlin Enum Class",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. ("enum class %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["kt.object"] = {
    label = "Kotlin Object",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. ("object %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["kt.annotation"] = {
    label = "Kotlin Annotation Class",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c)
        .. ("@Target(AnnotationTarget.CLASS)\n@Retention(AnnotationRetention.RUNTIME)\nannotation class %s(${cursor})\n"):format(
          c.name
        )
    end,
  },
  ["kt.file"] = {
    label = "Kotlin File",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. "${cursor}\n"
    end,
  },
  ["kt.main"] = {
    label = "Kotlin File with main()",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c) .. "fun main() {\n    ${cursor}\n}\n"
    end,
  },
  ["kt.test"] = {
    label = "Kotlin Test (JUnit 5)",
    category = "Kotlin",
    ext = "kt",
    langs = { "kotlin" },
    body = function(c)
      return kpkg(c)
        .. ("import kotlin.test.Test\nimport kotlin.test.assertEquals\n\nclass %s {\n\n    @Test\n    fun ${cursor}() {\n    }\n}\n"):format(
          c.name
        )
    end,
  },

  -- ---- Scala (Scala 3 syntax) ------------------------------------------
  ["scala.class"] = {
    label = "Scala Class",
    category = "Scala",
    ext = "scala",
    langs = { "scala" },
    body = function(c)
      return kpkg(c) .. ("class %s:\n  ${cursor}\n"):format(c.name)
    end,
  },
  ["scala.case-class"] = {
    label = "Scala Case Class",
    category = "Scala",
    ext = "scala",
    langs = { "scala" },
    body = function(c)
      return kpkg(c) .. ("final case class %s(${cursor})\n"):format(c.name)
    end,
  },
  ["scala.object"] = {
    label = "Scala Object",
    category = "Scala",
    ext = "scala",
    langs = { "scala" },
    body = function(c)
      return kpkg(c) .. ("object %s:\n  ${cursor}\n"):format(c.name)
    end,
  },
  ["scala.trait"] = {
    label = "Scala Trait",
    category = "Scala",
    ext = "scala",
    langs = { "scala" },
    body = function(c)
      return kpkg(c) .. ("trait %s:\n  ${cursor}\n"):format(c.name)
    end,
  },
  ["scala.sealed-trait"] = {
    label = "Scala Sealed Trait",
    category = "Scala",
    ext = "scala",
    langs = { "scala" },
    body = function(c)
      return kpkg(c) .. ("sealed trait %s\n${cursor}\n"):format(c.name)
    end,
  },
  ["scala.enum"] = {
    label = "Scala Enum",
    category = "Scala",
    ext = "scala",
    langs = { "scala" },
    body = function(c)
      return kpkg(c) .. ("enum %s:\n  case ${cursor}\n"):format(c.name)
    end,
  },
  ["scala.main"] = {
    label = "Scala @main App",
    category = "Scala",
    ext = "scala",
    langs = { "scala" },
    body = function(c)
      return kpkg(c) .. ("@main def %s(): Unit =\n  ${cursor}\n"):format(c.name)
    end,
  },

  -- ---- Groovy ----------------------------------------------------------
  ["groovy.class"] = {
    label = "Groovy Class",
    category = "Groovy",
    ext = "groovy",
    langs = { "groovy" },
    body = function(c)
      return jpkg(c) .. ("class %s {\n    ${cursor}\n}\n"):format(c.name)
    end,
  },
  ["groovy.script"] = {
    label = "Groovy Script",
    category = "Groovy",
    ext = "groovy",
    langs = { "groovy" },
    body = function()
      return "${cursor}\n"
    end,
  },
  ["groovy.spock"] = {
    label = "Groovy Spock Specification",
    category = "Groovy",
    ext = "groovy",
    langs = { "groovy" },
    body = function(c)
      return jpkg(c)
        .. ('import spock.lang.Specification\n\nclass %s extends Specification {\n\n    def "${cursor}"() {\n        expect:\n        true\n    }\n}\n'):format(
          c.name
        )
    end,
  },

  -- ---- Web / markup ---------------------------------------------------
  ["web.html"] = {
    label = "HTML5 File",
    category = "Web",
    ext = "html",
    langs = { "html", "htmldjango", "eruby", "php" },
    body = function(c)
      return ([[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
</head>
<body>
    ${cursor}
</body>
</html>
]]):format(c.name)
    end,
  },
  ["web.xhtml"] = {
    label = "XHTML File",
    category = "Web",
    ext = "xhtml",
    langs = { "html", "xhtml", "xml" },
    body = function(c)
      return ([[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
    <title>%s</title>
</head>
<body>
    ${cursor}
</body>
</html>
]]):format(c.name)
    end,
  },
  ["web.css"] = {
    label = "CSS Stylesheet",
    category = "Web",
    ext = "css",
    langs = { "css", "scss", "less", "html" },
    body = function(c)
      return ("/* %s */\n\n${cursor}\n"):format(c.name)
    end,
  },
  ["web.scss"] = {
    label = "SCSS Stylesheet",
    category = "Web",
    ext = "scss",
    langs = { "scss", "css", "html" },
    body = function(c)
      return ("// %s\n\n${cursor}\n"):format(c.name)
    end,
  },
  ["web.js"] = {
    label = "JavaScript Module",
    category = "Web",
    ext = "js",
    langs = { "javascript", "javascriptreact", "typescript", "html", "vue", "svelte" },
    body = function()
      return "${cursor}\n\nexport {};\n"
    end,
  },
  ["web.ts"] = {
    label = "TypeScript Module",
    category = "Web",
    ext = "ts",
    langs = { "typescript", "typescriptreact", "javascript", "vue", "svelte" },
    body = function()
      return "${cursor}\n\nexport {};\n"
    end,
  },
  ["web.vue"] = {
    label = "Vue Single-File Component",
    category = "Web",
    ext = "vue",
    langs = { "vue", "typescript", "javascript" },
    body = function()
      return [[<script setup lang="ts">
${cursor}
</script>

<template>
  <div></div>
</template>

<style scoped>
</style>
]]
    end,
  },
  ["web.svelte"] = {
    label = "Svelte Component",
    category = "Web",
    ext = "svelte",
    langs = { "svelte", "typescript", "javascript" },
    body = function()
      return '<script lang="ts">\n  ${cursor}\n</script>\n\n<div></div>\n\n<style>\n</style>\n'
    end,
  },

  -- ---- Data / config -----------------------------------------------
  ["data.xml"] = {
    label = "XML File",
    category = "Data & Config",
    ext = "xml",
    langs = { "xml", "html", "xhtml" },
    body = function(c)
      return ('<?xml version="1.0" encoding="UTF-8"?>\n<%s>\n    ${cursor}\n</%s>\n'):format(c.name, c.name)
    end,
  },
  ["data.json"] = {
    label = "JSON File",
    category = "Data & Config",
    ext = "json",
    langs = { "json", "jsonc", "javascript", "typescript" },
    body = function()
      return "{\n  ${cursor}\n}\n"
    end,
  },
  ["data.yaml"] = {
    label = "YAML File",
    category = "Data & Config",
    ext = "yaml",
    langs = { "yaml", "yaml.docker-compose", "helm" },
    body = function()
      return "---\n${cursor}\n"
    end,
  },
  ["data.toml"] = {
    label = "TOML File",
    category = "Data & Config",
    ext = "toml",
    langs = { "toml" },
    body = function(c)
      return ("# %s\n\n${cursor}\n"):format(c.name)
    end,
  },
  ["data.properties"] = {
    label = "Java .properties File",
    category = "Data & Config",
    ext = "properties",
    langs = { "jproperties", "java", "kotlin" },
    body = function(c)
      return ("# %s\n${cursor}\n"):format(c.name)
    end,
  },
  ["data.sql"] = {
    label = "SQL Script",
    category = "Data & Config",
    ext = "sql",
    langs = { "sql", "mysql", "plsql" },
    body = function(c)
      return ("-- %s\n\n${cursor}\n"):format(c.name)
    end,
  },
  ["data.http"] = {
    label = "HTTP Request File (.http)",
    category = "Data & Config",
    ext = "http",
    langs = { "http" },
    body = function(c)
      return ("### %s\nGET https://example.com/api\nAccept: application/json\n${cursor}\n"):format(c.name)
    end,
  },

  -- ---- DevOps ------------------------------------------------------
  ["devops.dockerfile"] = {
    label = "Dockerfile",
    category = "DevOps",
    ext = "",
    langs = { "dockerfile" },
    fixed_name = "Dockerfile",
    body = function()
      return 'FROM alpine:3.20\n\nWORKDIR /app\n\n${cursor}\n\nCMD ["sh"]\n'
    end,
  },
  ["devops.compose"] = {
    label = "Docker Compose File",
    category = "DevOps",
    ext = "yaml",
    langs = { "yaml", "yaml.docker-compose" },
    fixed_name = "compose",
    body = function()
      return "services:\n  ${cursor}\n"
    end,
  },
  ["devops.gitignore"] = {
    label = ".gitignore",
    category = "DevOps",
    ext = "",
    langs = { "gitignore" },
    fixed_name = ".gitignore",
    body = function()
      return "# Build output\n/target/\n/build/\n/dist/\n\n# IDE\n.idea/\n*.iml\n.vscode/\n\n# OS\n.DS_Store\n${cursor}\n"
    end,
  },
  ["devops.editorconfig"] = {
    label = ".editorconfig",
    category = "DevOps",
    ext = "",
    langs = { "editorconfig" },
    fixed_name = ".editorconfig",
    body = function()
      return "root = true\n\n[*]\ncharset = utf-8\nend_of_line = lf\ninsert_final_newline = true\nindent_style = space\nindent_size = 4\ntrim_trailing_whitespace = true\n${cursor}\n"
    end,
  },
  ["devops.shell"] = {
    label = "Shell Script (bash)",
    category = "DevOps",
    ext = "sh",
    langs = { "sh", "bash" },
    executable = true,
    body = function(c)
      return ("#!/usr/bin/env bash\n# %s\nset -euo pipefail\n\n${cursor}\n"):format(c.name)
    end,
  },
  ["devops.makefile"] = {
    label = "Makefile",
    category = "DevOps",
    ext = "",
    langs = { "make" },
    fixed_name = "Makefile",
    body = function()
      return ".PHONY: all\n\nall: ${cursor}\n"
    end,
  },

  -- ---- Misc languages -------------------------------------------
  ["misc.lua"] = {
    label = "Lua Module",
    category = "Other Languages",
    ext = "lua",
    langs = { "lua" },
    body = function(c)
      return ("-- %s\n\nlocal M = {}\n\n${cursor}\n\nreturn M\n"):format(c.name)
    end,
  },
  ["misc.python"] = {
    label = "Python Module",
    category = "Other Languages",
    ext = "py",
    langs = { "python" },
    body = function(c)
      return ('"""%s."""\n\n${cursor}\n'):format(c.name)
    end,
  },
  ["misc.go"] = {
    label = "Go File",
    category = "Other Languages",
    ext = "go",
    langs = { "go" },
    body = function(c)
      local pkg = vim.fs.basename(c.dir)
      if pkg == "" or pkg:match("[^%w_]") then
        pkg = "main"
      end
      return ("package %s\n\n${cursor}\n"):format(pkg)
    end,
  },
  ["misc.markdown"] = {
    label = "Markdown Document",
    category = "Other Languages",
    ext = "md",
    langs = { "markdown" },
    body = function(c)
      return ("# %s\n\n${cursor}\n"):format(c.name)
    end,
  },
  ["misc.readme"] = {
    label = "README.md",
    category = "Other Languages",
    ext = "md",
    langs = { "markdown" },
    fixed_name = "README",
    body = function(c)
      local title = vim.fs.basename(c.root)
      return ("# %s\n\n${cursor}\n\n## Getting started\n\n## License\n"):format(title ~= "" and title or c.name)
    end,
  },
}
