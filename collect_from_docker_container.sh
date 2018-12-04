set -ex && mkdir -p ./build/release/bin
set -ex && docker create --name sevabit-gui-container sevabit-gui-image
set -ex && docker cp sevabit-gui-container:/src/build/release/bin/ ./build/release/
set -ex && docker rm sevabit-gui-container
