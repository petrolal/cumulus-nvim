-- TetraVim JVM Project Generator -- curated catalogs.
--
-- Static data carved out of lua/tetravim/util/jvm/project_wizard.lua: the curated
-- Spring Boot dependency list, the quick-start presets, and the Maven archetype
-- catalog. The wizard re-exports these as `project_wizard.SPRING_DEPENDENCIES`,
-- `.SPRING_PRESETS` and `.MAVEN_ARCHETYPES`. Dynamic catalogs (start.spring.io,
-- Maven Central) are fetched at runtime and stay in the parent module.

return {
  --- Curated Spring Boot dependency catalog with icons and descriptions.
  SPRING_DEPENDENCIES = {
    -- Web
    { id = "web", name = "Spring Web", desc = "RESTful APIs, Spring MVC, embedded Tomcat" },
    { id = "webflux", name = "Spring Reactive Web", desc = "Reactive web apps with Netty" },
    -- Data & Persistence
    { id = "data-jpa", name = "Spring Data JPA", desc = "SQL persistence with Hibernate & JPA" },
    { id = "data-jdbc", name = "Spring Data JDBC", desc = "Lightweight JDBC repository support" },
    { id = "data-mongodb", name = "Spring Data MongoDB", desc = "Document-based NoSQL persistence" },
    { id = "data-redis", name = "Spring Data Redis", desc = "Redis key-value data storage & cache" },
    -- SQL Databases
    { id = "postgresql", name = "PostgreSQL Driver", desc = "PostgreSQL JDBC Driver" },
    { id = "mysql", name = "MySQL Driver", desc = "MySQL JDBC Driver" },
    { id = "h2", name = "H2 Database", desc = "In-memory database for dev/testing" },
    { id = "flyway", name = "Flyway Migration", desc = "Version-controlled database migrations" },
    -- Developer Tools
    { id = "lombok", name = "Lombok", desc = "Boilerplate annotations (@Getter, @Setter, @Builder)" },
    { id = "devtools", name = "Spring Boot DevTools", desc = "Fast restarts and LiveReload" },
    { id = "docker-compose", name = "Docker Compose Support", desc = "Auto-launch containers in dev" },
    { id = "configuration-processor", name = "Config Processor", desc = "Metadata for @ConfigurationProperties" },
    -- Security
    { id = "security", name = "Spring Security", desc = "Authentication and access control" },
    { id = "oauth2-client", name = "OAuth2 Client", desc = "Spring Security OAuth2 Client & Login" },
    {
      id = "oauth2-resource-server",
      name = "OAuth2 Resource Server",
      desc = "Spring Security OAuth2 Resource Server (JWT)",
    },
    -- Ops & Monitoring
    { id = "actuator", name = "Spring Boot Actuator", desc = "Production-ready health, metrics and info endpoints" },
    { id = "prometheus", name = "Prometheus Metrics", desc = "Micrometer metrics for Prometheus scraping" },
    -- Validation & Serialization
    { id = "validation", name = "Validation", desc = "Bean Validation with Hibernate Validator" },
    -- Testing
    { id = "testcontainers", name = "Testcontainers", desc = "JUnit integration with lightweight Docker containers" },
    -- Cloud / Messaging
    { id = "kafka", name = "Spring for Apache Kafka", desc = "Kafka streams and message listeners" },
    { id = "amqp", name = "Spring for RabbitMQ", desc = "RabbitMQ messaging" },
  },

  --- Popular Spring Boot presets for fast scaffolding.
  SPRING_PRESETS = {
    {
      name = "🚀 REST API (Web + Lombok + Actuator + Validation)",
      deps = { "web", "lombok", "actuator", "validation" },
    },
    {
      name = "💾 Full-Stack DB (Web + Data JPA + PostgreSQL + Lombok + Flyway)",
      deps = { "web", "data-jpa", "postgresql", "lombok", "flyway", "actuator" },
    },
    {
      name = "🔒 Secure REST API (Web + Security + JPA + Postgres + Lombok)",
      deps = { "web", "security", "data-jpa", "postgresql", "lombok", "actuator" },
    },
    {
      name = "🤖 Spring AI / GenAI (OpenAI + Ollama + Web + Lombok)",
      deps = { "web", "spring-ai-openai", "spring-ai-ollama", "lombok", "actuator" },
    },
    {
      name = "⚡ Reactive WebFlux (WebFlux + R2DBC + Postgres + Lombok)",
      deps = { "webflux", "postgresql", "lombok", "actuator" },
    },
    {
      name = "🌱 Minimal Web (Spring Web only)",
      deps = { "web" },
    },
    {
      name = "🎯 Browse & Select All Dependencies (200+ items, VSCode / IntelliJ flow)...",
      deps = nil, -- triggers interactive multi-selection
    },
    {
      name = "⌨️  Manual Input (comma-separated IDs)",
      deps = "manual",
    },
  },

  --- Curated Maven archetypes catalog with icons and descriptions.
  MAVEN_ARCHETYPES = {
    {
      groupId = "org.apache.maven.archetypes",
      artifactId = "maven-archetype-quickstart",
      version = "RELEASE",
      icon = "☕ ",
      name = "Java Application (quickstart)",
      desc = "Standard Java console/service application with JUnit",
    },
    {
      groupId = "org.apache.maven.archetypes",
      artifactId = "maven-archetype-webapp",
      version = "RELEASE",
      icon = "🌐 ",
      name = "Java Web Application (webapp)",
      desc = "Servlet/JSP web application with standard WEB-INF layout",
    },
    {
      groupId = "org.apache.maven.archetypes",
      artifactId = "maven-archetype-simple",
      version = "RELEASE",
      icon = "📦 ",
      name = "Simple Project (simple)",
      desc = "Minimal bare-bones Maven project structure",
    },
    {
      groupId = "org.jetbrains.kotlin",
      artifactId = "kotlin-archetype-jvm",
      version = "RELEASE",
      icon = "󱈙 ",
      name = "Kotlin JVM Application",
      desc = "Standard Kotlin application configured with kotlin-stdlib",
    },
    {
      groupId = "org.openjfx",
      artifactId = "javafx-archetype-simple",
      version = "RELEASE",
      icon = "🖥️ ",
      name = "JavaFX Desktop Application",
      desc = "Modern JavaFX GUI desktop application skeleton",
    },
    {
      groupId = "org.apache.maven.archetypes",
      artifactId = "maven-archetype-plugin",
      version = "RELEASE",
      icon = "🔌 ",
      name = "Maven Plugin (mojo)",
      desc = "Skeleton for developing custom Maven plugins and Mojos",
    },
    {
      groupId = "org.apache.maven.archetypes",
      artifactId = "maven-archetype-archetype",
      version = "RELEASE",
      icon = "📐 ",
      name = "Archetype Template Creator",
      desc = "Meta-project to create and publish custom Maven archetypes",
    },
    {
      custom = true,
      icon = "✨ ",
      name = "Custom Archetype...",
      desc = "Specify any groupId:artifactId:version",
    },
    {
      search_central = true,
      icon = "🌐 ",
      name = "Search Maven Central Catalog...",
      desc = "Filter 3,500+ archetypes by keyword (e.g. spark, camel, quarkus, javafx)",
    },
  },
}
