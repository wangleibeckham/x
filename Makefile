SHELL=/bin/bash -o pipefail

export PATH := .bin:${PATH}

GO_DEPENDENCIES = github.com/ory/go-acc \
				  github.com/ory/x/tools/listx \
				  github.com/jandelgado/gcov2lcov  \
				  github.com/golang/mock/mockgen

define make-go-dependency
  # go install is responsible for not re-building when the code hasn't changed
  .bin/$(notdir $1): go.mod go.sum Makefile
		GOBIN=$(PWD)/.bin/ go install $1
endef
$(foreach dep, $(GO_DEPENDENCIES), $(eval $(call make-go-dependency, $(dep))))
$(call make-lint-dependency)

.bin/cli: go.mod go.sum Makefile
		go build -o .bin/cli -tags sqlite github.com/ory/cli

.PHONY: format
format:
		goreturns -w -i -local github.com/ory $$(listx . | grep -v "go_mod_indirect_pins.go")

.bin/golangci-lint: Makefile
		bash <(curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh) -d -b .bin v1.28.3

.PHONY: test
test:
		make resetdb
		export TEST_DATABASE_POSTGRESQL=postgres://postgres:secret@127.0.0.1:3445/hydra?sslmode=disable; export TEST_DATABASE_COCKROACHDB=cockroach://root@127.0.0.1:3446/defaultdb?sslmode=disable; export TEST_DATABASE_MYSQL='mysql://root:secret@tcp(127.0.0.1:3444)/mysql?parseTime=true&multiStatements=true'; go test -race -tags sqlite ./...

.PHONY: resetdb
resetdb:
		docker kill hydra_test_database_mysql || true
		docker kill hydra_test_database_postgres || true
		docker kill hydra_test_database_cockroach || true
		docker rm -f hydra_test_database_mysql || true
		docker rm -f hydra_test_database_postgres || true
		docker rm -f hydra_test_database_cockroach || true
		docker run --rm --name hydra_test_database_mysql -p 3444:3306 -e MYSQL_ROOT_PASSWORD=secret -d mysql:8.0
		docker run --rm --name hydra_test_database_postgres -p 3445:5432 -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=hydra -d postgres:11.8
		docker run --rm --name hydra_test_database_cockroach -p 3446:26257 -d cockroachdb/cockroach:v20.2.3 start --insecure

.PHONY: lint
lint: .bin/golangci-lint
		GO111MODULE=on golangci-lint run -v ./...

.PHONY: migrations-render
migrations-render: .bin/cli
		cli dev pop migration render networkx/migrations/templates networkx/migrations/sql

.PHONY: migrations-render-replace
migrations-render-replace: .bin/cli
		cli dev pop migration render -r networkx/migrations/templates networkx/migrations/sql
