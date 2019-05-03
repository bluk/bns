workflow "Build on push" {
  on = "push"
  resolves = ["Build and Test Package"]
}

action "Build and Test Package" {
  uses = "docker://bluk/docker-swift-build-tools@sha256:19accd7a244200413706b62161e9d238792b7035e06b98199bd0ab3bf1f6e2f8"
  args = "test"
  runs = "swift"
}
