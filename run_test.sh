export TEST_HELM_PATH=/tmp/rook-tests-scripts-helm/helm
export TEST_BASE_DIR=WORKING_DIR
export TEST_SCRATCH_DEVICE=/dev/vdb

go test -v -timeout 1800s -run CephSmokeSuite github.com/rook/rook/tests/integration
