#!/usr/bin/env python3
"""Structural tests for the air-gap infrastructure and media contract."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    """Read one repository file as UTF-8 text."""
    return (ROOT / relative_path).read_text(encoding="utf-8")


class InfrastructureContractTest(unittest.TestCase):
    """Protect the properties that make the deployed VM an air gap."""

    def test_vm_has_an_80_gib_os_disk_and_only_private_networking(self) -> None:
        main = read("tofu/main.tf")
        self.assertIn("disk_size_gb         = 80", main)
        self.assertIn("private_ip_address_allocation = \"Static\"", main)
        forbidden = (
            "azurerm_public_ip",
            "azurerm_nat_gateway",
            "azurerm_lb",
            "azurerm_application_gateway",
            "azurerm_virtual_network_gateway",
        )
        for token in forbidden:
            self.assertNotIn(token, main)

    def test_subnet_and_nsg_fail_closed_on_outbound_traffic(self) -> None:
        main = read("tofu/main.tf")
        self.assertRegex(main, r"default_outbound_access_enabled\s*=\s*false")
        self.assertRegex(
            main,
            re.compile(
                r'name\s*=\s*"deny-all-egress".*?direction\s*=\s*"Outbound"'
                r'.*?access\s*=\s*"Deny".*?destination_address_prefix\s*=\s*"\*"',
                re.DOTALL,
            ),
        )
        self.assertNotRegex(main, re.compile(r'direction\s*=\s*"Outbound".*?access\s*=\s*"Allow"', re.DOTALL))

    def test_vm_uses_prebaked_image_and_read_only_offline_media(self) -> None:
        main = read("tofu/main.tf")
        variables = read("tofu/variables.tf")
        self.assertRegex(main, r"source_image_id\s*=\s*var\.source_image_id")
        self.assertIn("managed_disk_id    = var.offline_media_disk_id", main)
        self.assertIn("caching            = \"ReadOnly\"", main)
        self.assertIn("lun                = 10", main)
        self.assertIn('variable "source_image_id"', variables)
        self.assertIn('variable "offline_media_disk_id"', variables)
        self.assertNotIn("source_image_reference", main)

    def test_host_firewall_defaults_to_no_egress(self) -> None:
        rules = read("image/runtime/90-plot-airgap.nft")
        self.assertIn("hook output priority filter; policy drop;", rules)
        self.assertIn("oifname \"lo\" accept", rules)
        output_chain = rules.split("chain output", 1)[1]
        self.assertNotIn("ct state established,related accept", output_chain)

    def test_runtime_uses_podman_and_loopback_only_services(self) -> None:
        plot = read("image/runtime/plot.container")
        model = read("image/runtime/llama.container")
        self.assertIn("Image=localhost/plot-appliance:airgap", plot)
        self.assertIn("Environment=PLOT_LISTEN=127.0.0.1:8080", plot)
        self.assertIn("Network=host", plot)
        self.assertNotIn("PublishPort=", plot)
        self.assertIn("Image=localhost/llama-server:airgap", model)
        self.assertIn("--host 127.0.0.1 --port 8081", model)
        self.assertIn("Network=host", model)
        self.assertNotIn("PublishPort=", model)
        self.assertIn("/models/default.gguf", model)

    def test_rhel9_profile_prepares_connected_image_with_dnf(self) -> None:
        profile = read("image/profiles/rhel9.env")
        prepare = read("image/prepare-rhel9.sh")
        self.assertIn("IMAGE_PUBLISHER=RedHat", profile)
        self.assertIn("IMAGE_OFFER=RHEL", profile)
        self.assertIn("IMAGE_SKU=9-lvm-gen2", profile)
        self.assertIn("dnf -y install", prepare)
        for package in ("podman", "nftables", "curl", "util-linux"):
            self.assertIn(package, prepare)
        self.assertLess(prepare.index("dnf -y install"), prepare.rindex("runtime/install.sh"))

    def test_rhel9_profile_has_one_firewall_owner(self) -> None:
        prepare = read("image/prepare-rhel9.sh")
        install = read("image/runtime/install.sh")
        self.assertIn("systemctl disable --now firewalld.service", prepare)
        self.assertIn("systemctl mask firewalld.service", prepare)
        self.assertIn("systemctl disable --now nftables.service", prepare)
        self.assertIn("systemctl enable plot-airgap-firewall.service", install)

    def test_rhel9_runtime_keeps_quadlets_selinux_labeled(self) -> None:
        prepare = read("image/prepare-rhel9.sh")
        install = read("image/runtime/install.sh")
        plot = read("image/runtime/plot.container")
        model = read("image/runtime/llama.container")
        self.assertIn("PLOT_AIRGAP_RUNTIME_DIR", prepare)
        self.assertIn("PLOT_AIRGAP_RUNTIME_DIR", install)
        self.assertIn("/etc/containers/systemd", install)
        self.assertIn("restorecon -RFv /etc/containers/systemd /var/lib/plot", install)
        self.assertIn(":Z", plot)
        self.assertIn(":ro,Z", plot)
        self.assertIn(":ro,Z", model)
        self.assertNotIn("setenforce 0", prepare)

    def test_image_builder_accepts_an_explicit_rhel9_profile(self) -> None:
        builder = read("image/build-image.sh")
        self.assertIn("<profile>", builder)
        self.assertIn("image/profiles/${profile}.env", builder)
        self.assertIn("IMAGE_SKU", builder)
        self.assertIn("prepare-rhel9.sh", builder)

    def test_vm_creation_has_access_and_console_prerequisites(self) -> None:
        main = read("tofu/main.tf")
        variables = read("tofu/variables.tf")
        self.assertIn("admin_ssh_key {", main)
        self.assertIn("public_key = var.admin_ssh_public_key", main)
        self.assertIn('variable "admin_ssh_public_key"', variables)
        self.assertIn("boot_diagnostics {}", main)

    def test_bundle_builder_never_pulls_and_emits_checksums(self) -> None:
        script = read("scripts/build-offline-bundle.sh")
        self.assertIn("podman image exists", script)
        self.assertIn("podman save", script)
        self.assertIn("sha256sum", script)
        self.assertNotIn("podman pull", script)
        self.assertNotIn("curl ", script)
        self.assertNotIn("wget ", script)

    def test_media_import_verifies_bytes_before_loading_images(self) -> None:
        script = read("image/runtime/import-media.sh")
        self.assertIn("findmnt", script)
        self.assertIn("grep -qx ro", script)
        self.assertLess(script.index("sha256sum -c"), script.index("podman load"))
        self.assertIn("install -m 0444", script)
        self.assertIn("systemctl start llama.service", script)
        self.assertNotIn("systemctl start plot.service", script)

    def test_no_ingestion_command_is_part_of_vm_boot(self) -> None:
        for relative_path in (
            "image/runtime/import-media.sh",
            "image/runtime/plot.container",
            "image/runtime/llama.container",
        ):
            self.assertNotIn("corestory ingest", read(relative_path))

    def test_documentation_states_the_proof_and_model_boundary(self) -> None:
        readme = read("README.md")
        self.assertIn("80 GiB", readme)
        self.assertIn("no public IP", readme)
        self.assertIn("deny-all outbound", readme)
        self.assertIn("Qwen2.5-Coder-3B-Instruct", readme)
        self.assertIn("Kimi", readme)
        self.assertIn("does not fit", readme)
        self.assertIn("No ingestion", readme)

    def test_documentation_states_rhel_licensing_and_cloud_boundaries(self) -> None:
        readme = read("README.md")
        self.assertIn("RedHat:RHEL:9-lvm-gen2", readme)
        self.assertIn("PAYG", readme)
        self.assertIn("BYOS", readme)
        self.assertIn("Azure Government", readme)
        self.assertIn("21Vianet", readme)
        self.assertIn("private plans", readme)

    def test_ci_is_read_only_and_runs_the_repository_gate(self) -> None:
        workflow = read(".github/workflows/ci.yml")
        self.assertIn("contents: read", workflow)
        self.assertIn("./scripts/check.sh", workflow)
        self.assertNotIn("tofu apply", workflow)
        self.assertNotIn("permissions: write", workflow)


if __name__ == "__main__":
    unittest.main()
