workflow "Build on push" {
  on = "push"
  resolves = ["Build and Test Package"]
}

action "Build and Test Package" {
  uses = "docker://bluk/docker-swift-build-tools@sha256:da3c2a2743cd7c1f878a7f8fd1f561625908b256f391c4cc6442b41a35665931"
  args = "test"
  runs = "swift"
}
