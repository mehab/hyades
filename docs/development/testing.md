# Testing

## Introduction

We generally aim for a test coverage of ~80%. This is also true for new code introduced through pull requests.
We value integration tests more than unit tests, and try to avoid using mocks as much as possible.
If reaching the 80% test coverage requires us to write tests that don't really test anything meaningful,
or require loads of mocking, we rather take lower coverage than writing those tests.

We use [Testcontainers], [Wiremock], and [GreenMail] to test how the system interacts with the outside world.

## Unit Tests

### `hyades`

TBD

### `hyades-apiserver`

!!! warning
    To reduce execution time of the test suite in CI, the PostgreSQL Testcontainer is [reused].
    While tables are truncated after each test, sequences (e.g. for `ID` columns) won't be reset.
    As a consequence, you should not assert on IDs of database records.

### `hyades-frontend`

There are currently no unit tests for the frontend.

## Integration Tests

### `hyades`

Integration tests in the `hyades` repository are implemented as [@QuarkusIntegrationTest]. 
As such, they are executed against an actual build artifact (JAR, container, or native executable).

Class names of integration tests are suffixed with `IT` instead of `Test`.

#### Execution

Integration tests can be launched individually through your IDE, or all at once using Maven:

```shell
mvn -pl '!e2e' clean verify failsafe:integration-test -DskipITs=false
```

To limit the test run to specific modules, use `-pl <module>`, for example:

```shell
mvn -pl vulnerability-analyzer clean verify failsafe:integration-test -DskipITs=false
```

#### Execution in CI

In CI, integration tests are executed:

* Against all JARs, as part of the `CI / Test` workflow
* Against native executables, as part of the `CI / Test Native Image` workflow(s)

Both workflows run for pushes and pull requests to the `main` branch.

### `hyades-apiserver`

The API server repository does not currently differentiate between unit- and integration-tests.

### `hyades-frontend`

There are currently no integration tests for the frontend.

## End-to-End Tests

End-to-End tests spin up containers for all services of the system. The test environment is torn down
and rebuilt for every test case. Containers are started and managed using [Testcontainers].

The tests are located in the [`e2e`](https://github.com/DependencyTrack/hyades/tree/main/e2e) module of the
`hyades` repository. Container images used are defined in the
[`AbstractE2ET`](https://github.com/DependencyTrack/hyades/blob/main/e2e/src/test/java/org/dependencytrack/e2e/AbstractE2ET.java)
class.

Image versions can be overwritten using the following environment variables:

* `APISERVER_VERSION`
* `HYADES_VERSION`

### Execution

Tests can be launched individually through your IDE, or all at once using Maven:

```shell
mvn -pl e2e clean verify -Pe2e-all
```

To test against local changes:

1. [Build container images](./building.md#containers) for the modified services
2. Update the image tags in `AbstractE2ET` accordingly
3. Run e2e tests as detailed above

### Execution in CI

In CI, end-to-end tests are executed for every push to the `main` branch, as well as every night at 12AM.

They can additionally be run manually, via the GitHub Actions UI. Both the API server and Hyades version
can be customized before execution.

### E2E Testing with Playwright (BDD)

Apart from the current E2E-Testing approach, there will be another approach managed from now on that uses **Playwright BDD** (Behaviour-Driven-Development).
The new approach provides a more simplified understanding on what is executed in each test.
More on that can be found inside [Playwright README](https://github.com/DependencyTrack/hyades/blob/master/e2e/playwright-tests/README.md)

*V1 will be managed inside the Hyades repository. 
The next version will be decoupled into its own repository, abstracting it from Hyades entirely and also allowing for DTrackV4 (aka the Monolith) to be tested.*

## Manual Tests

### Docker Compose

The easiest way to test the entire system is by using Docker Compose.

A [`docker-compose.yml` file is provided](https://github.com/DependencyTrack/hyades/blob/main/docker-compose.yml)
in the `DependencyTrack/hyades` repository.

Without any profile specified, `docker compose up -d` will launch:

* PostgreSQL
* Kafka (currently Redpanda)
* Kafka UI (currently Redpanda Console)

To launch Dependency-Track services, use the `demo` profile:

```shell
docker compose up -d --profile demo
```

To test different versions of the services, simply modify the `image` property of the respective Compose `service`.

### API Server

When testing changes that are limited to the API server, such as updates to the REST API,
it's possible to launch the API server in [dev services](../reference/configuration/api-server.md#devservicesenabled) mode:

```shell
mvn -Penhance -Pdev-services jetty:run -Dlogback.configurationFile=src/main/docker/logback.xml
```

The container images used may be configured via:

* [`dev.services.image.frontend`](../reference/configuration/api-server.md#devservicesimagefrontend)
* [`dev.services.image.kafka`](../reference/configuration/api-server.md#devservicesimagekafka)
* [`dev.services.image.postgresql`](../reference/configuration/api-server.md#devservicesimagepostgres)

[@QuarkusIntegrationTest]: https://quarkus.io/guides/getting-started-testing#quarkus-integration-test
[GreenMail]: https://greenmail-mail-test.github.io/greenmail/
[Testcontainers]: https://testcontainers.com/
[WireMock]: https://wiremock.org/
[reused]: https://java.testcontainers.org/features/reuse/