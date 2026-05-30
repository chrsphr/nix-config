# SSH public keys, centralised so a rotation is one edit.
# Import as a plain data file, e.g.:
#   let keys = import ./modules/keys.nix; in
#   users.users.chris.openssh.authorizedKeys.keys = [ keys.chris ];
{
  chris = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK1z+ixouoLpNHXciINsW1Jlvcmnr9E2ekFXCvvjBxfh";
}
