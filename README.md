# CoreStory - Azure Estate Intelligence Platform

This repository separates connected preparation from disconnected operation.
Terraform creates one private Azure VM with an 80 GiB OS disk, an offline-transfer disk, no public IP, no NAT gateway, subnet default outbound access disabled, and a deny-all outbound network security group rule.
The guest adds a second independent boundary: nftables drops every forwarded and outbound packet except loopback.

The repository follows the neighboring `infra` repository's Azure/Terraform conventions without modifying it.
Nothing here has been provisioned.
No model weights or container archives are stored in this repository.

The public engineering source is `https://github.com/CoreStoryAI/plot-airgap-poc`.
This remains a non-production proof until a reviewed Azure plan and runtime evidence close the deliberate limitations below.

## What the proof establishes

| Layer | Enforced control | Evidence |
| --- | --- | --- |
| Azure addressing | The NIC has only `10.80.0.10`; no `azurerm_public_ip` exists. | `terraform/main.tf`, `terraform output network_controls` |
| Azure routing | The subnet sets `default_outbound_access_enabled = false`; there is no NAT or gateway resource. | `terraform/main.tf` and contract tests |
| Azure filtering | The NSG's only outbound rule is `deny-all-egress`. | `terraform/main.tf` and contract tests |
| Guest filtering | The nftables output and forward chains default to drop; output permits loopback only. | `image/runtime/90-plot-airgap.nft` |
| Workload networking | Both Podman Quadlet units share the host namespace but bind their listeners to `127.0.0.1`; the guest firewall permits loopback and drops other output. | `image/runtime/*.container`, `image/runtime/90-plot-airgap.nft` |
| Software supply | A connected station exports already-local OCI images and a GGUF file with SHA-256 checksums. | `scripts/build-offline-bundle.sh` |
| Transfer | The VM receives a managed disk at LUN 10; the operator must mount it read-only, and import refuses writable mounts and verifies checksums before `podman load`. | `terraform/main.tf`, `image/runtime/import-media.sh` |

These controls demonstrate no IP egress from the VM at runtime.
They do not protect against Azure control-plane actions by subscription administrators, malicious image publishers, hypervisor compromise, physical exfiltration, or data copied deliberately to replacement media.
An operator may permit inbound SSH from one private CIDR, but return traffic is blocked because the host output chain allows loopback only.
Use Azure serial console or a temporary audited maintenance image to administer the strict runtime profile.
Managed boot diagnostics is enabled so the serial-console path exists without VM network egress.

## Architecture

```text
connected build station                     isolated Azure VNet
+----------------------------------+         +----------------------------------+
| build Plot appliance locally     |         | private VM, 80 GiB OS disk      |
| stage llama.cpp OCI image        |         | Podman + nftables               |
| select local GGUF                |         | plot: 127.0.0.1:8080            |
| podman save + SHA-256 manifest   |--disk-->| llama: 127.0.0.1:8081 (/v1/*)  |
+----------------------------------+ read-only+----------------------------------+
                  no registry, package mirror, model hub, NAT, or public IP
```

The two containers use host networking solely to share host loopback; each process binds explicitly to `127.0.0.1`, and nftables blocks non-loopback output.
The image must be baked while connected.
The runtime VM never installs packages and does not contact a registry or model hub.

## Model choice and Kimi boundary

The practical default is a configurable GGUF for **Qwen2.5-Coder-3B-Instruct**, normally a Q4_K_M quantization.
A roughly 2–3 GiB model leaves room on an 80 GiB disk for the operating system, two OCI images, Plot state, and a small demonstration corpus.
The default `Standard_D8s_v5` VM has enough RAM for CPU inference, although performance must be measured on the selected region and SKU.

Kimi does not fit this 80 GiB proof of concept and is not the default.
A Kimi K2-class checkpoint is hundreds of billions to a trillion parameters depending on the release; even aggressive quantization and runtime overhead exceed this 80 GiB PoC and typically require a multi-GPU or multi-node design.
Treat Kimi as a parameterized replacement payload only: increase OS or data-disk capacity, select suitable GPU memory, bake a compatible runtime, and set `MODEL_FILE` to a locally staged GGUF or other supported artifact.
Do not describe that larger architecture as this PoC.

No downloader is included intentionally.
Model license review and checksum approval happen in the connected staging environment before transfer.

## Connected preparation

1. Build and verify the Plot appliance from `/Users/rploski/work/projects/plot-container-poc`.
2. Tag that verified image as `localhost/plot-appliance:airgap`.
3. Build or load an approved llama.cpp server image as `localhost/llama-server:airgap`.
4. Place the approved small GGUF at `models/default.gguf` or set `MODEL_FILE`.
5. Build the bundle without network access by the script itself:

```sh
PLOT_IMAGE=localhost/plot-appliance:airgap \
LLAMA_IMAGE=localhost/llama-server:airgap \
MODEL_FILE=models/default.gguf \
./scripts/build-offline-bundle.sh bundle
```

The script requires each image and model to exist locally.
It never pulls or downloads.
Copy `bundle/` into an ext4 filesystem on removable media or into a managed-disk snapshot through an approved import station.
Attach the resulting managed disk as `offline_media_disk_id` and mount its filesystem read-only inside the guest.
Azure's Linux data-disk attachment does not expose a read-only flag; `caching = "ReadOnly"` controls caching and is not a write-protection claim.

The image-baking files under `image/` document the guest payload.
`image/template.json` is deliberately a non-provisioning placeholder because an Azure Image Builder template needs organization-specific identity, network, gallery, and base-image decisions.
The explicit `rhel9` profile uses the PAYG Marketplace source family `RedHat:RHEL:9-lvm-gen2:<pinned-version>` and `image/prepare-rhel9.sh` for connected preparation.
The approved image pipeline must stage this repository at `/tmp/plot-airgap`, invoke the preparation script as root on RHEL 9, and publish the result as an immutable Azure Compute Gallery image version.
The script installs Podman, nftables, curl, `util-linux`, and SELinux tooling with `dnf`, then removes the package cache before image publication.
It disables and masks both `firewalld.service` and the distribution `nftables.service` so only `plot-airgap-firewall.service` owns the active ruleset.
The Podman workloads remain Quadlets, and their bind mounts use `:Z` or `:ro,Z` labels while SELinux stays enforcing.

Run the integration seam with an explicit profile:

```sh
./image/build-image.sh rhel9 <resource-group> <gallery-name> <image-definition>
```

The placeholder submits only an organization-supplied Image Builder template; it does not infer identity, VNet, gallery destination, or a Marketplace version.
Pin the exact Marketplace source version in that approved template rather than using `latest`.
Terraform rejects an image definition or `latest` alias in favor of a version ID.

### RHEL licensing and cloud boundary

The `RedHat:RHEL:9-lvm-gen2` source family is the standard-repository PAYG path and carries the applicable RHEL software charge while the build VM exists.
BYOS uses Red Hat Gold Images/private plans, avoids the PAYG RHEL premium, and requires the customer to supply valid Red Hat entitlement and update access before the image is disconnected.
BYOS private plans are not supported in CSP subscriptions, so availability must be verified for the target subscription instead of assuming the PAYG identifier can be reused.
Microsoft documents RHEL Marketplace images and BYOS Gold Images for Azure public and Azure Government, but the operator must query the selected cloud and region for the exact offer, SKU, and version before approving the build.
These images are not available in Microsoft Azure operated by 21Vianet; this repository does not claim support there.
Azure Government also requires its own CLI cloud selection, identity, networking, gallery, pricing review, and approved Image Builder template.
The runtime Terraform remains unchanged because it consumes only an immutable gallery version ID; PAYG, BYOS, and cloud selection belong to connected image preparation.

## Provisioning handoff

No apply was run for this proof.
When reviewers approve provisioning:

```sh
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Replace every placeholder with reviewed Azure resource IDs.
terraform -chdir=terraform init

terraform -chdir=terraform plan -out=plot-airgap.tfplan
# Review the plan for exactly one NIC, no public IP/NAT/gateway,
# default outbound disabled, deny-all outbound, and an 80 GiB OS disk.
terraform -chdir=terraform apply plot-airgap.tfplan
```

Do not use remote-exec, cloud-init package installation, or a moving marketplace image.
Those paths either need egress or weaken provenance.

## Offline import and startup

Mount the media read-only at `/media/airgap`, then run:

```sh
sudo plot-import-media /media/airgap
```

The importer verifies `SHA256SUMS`, loads both OCI archives, installs the model read-only, and starts only the OpenAI-compatible model server.
Plot remains stopped because its current appliance ingests the mounted repository before serving.
**No ingestion is launched by this repository.**
After a human explicitly approves the demonstration corpus, mount it read-only at `/var/lib/plot/workspace` and start Plot with `sudo systemctl start plot.service`.

The local endpoints are:

- Plot: `http://127.0.0.1:8080/`
- OpenAI-compatible model API: `http://127.0.0.1:8081/v1/`

A local reverse proxy or SSH tunnel would require a separately reviewed host-firewall exception.
The shipped strict rules expose neither service beyond loopback.

## Runtime proof

Run from the VM console:

```sh
sudo ./scripts/validate-runtime.sh
sudo nft list ruleset
ip address
ip route
podman ps
curl --fail http://127.0.0.1:8081/v1/models
```

A blog demonstration should capture the Terraform plan, Azure NIC effective routes and NSG rules, the nftables ruleset, a failed external HTTPS probe, a failed external DNS lookup, and a successful loopback model response.
A failed `curl` alone is not proof; the static controls and effective Azure state provide the causal evidence.

## Local validation

```sh
python3 -m unittest discover -s tests -v
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
shellcheck scripts/*.sh image/*.sh image/runtime/*.sh
```

`terraform init` downloads the provider unless it is already cached, so it belongs to connected development and not the air-gapped VM.
The Python contract suite is dependency-free and validates the zero-egress design without Azure credentials.

## Deliberate limitations

- The PoC has not been provisioned, so Azure effective-route and live NSG evidence remain a deployment acceptance step.
- The Azure Image Builder template is a documented integration seam, not a runnable builder.
- No large weights were fetched and no corpus was ingested.
- The read-only disk is a transport mechanism, not content trust by itself; checksum approval must occur before media creation.
- Plot's current container appliance ingests on startup, so it is intentionally not started automatically.
- Availability Zone support, confidential VM support, Secure Boot, vTPM, disk encryption keys, backup, monitoring, and operator access require environment-specific design before production use.
