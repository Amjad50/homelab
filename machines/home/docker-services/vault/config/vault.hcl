ui = true
disable_mlock = true

api_addr = "https://vault.home.amsh.dev"
cluster_addr = "http://vault:8201"

listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = 1
}

storage "raft" {
  path = "/vault/file"
  node_id = "home-vault"
}
