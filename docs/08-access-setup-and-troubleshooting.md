# Access Setup and Troubleshooting

## Recommended Access Model

Learners access labs through Tailscale.

The recommended connection flow is:

1. Learner installs Tailscale.
2. Learner signs in to the lab tailnet.
3. Learner starts a lab.
4. Lab instance joins the tailnet.
5. Learner connects with Tailscale SSH.

## Install Tailscale

Learner should install Tailscale on their local machine.

After installation, learner should sign in using the provided lab identity.

## Verify Connection

Command:

    tailscale status

Expected result:

- The learner device appears in the tailnet.
- The lab instance appears when the lab is Ready.

## Connect to a Lab

Example command:

    tailscale ssh student@linux-beginner-12345.cloudybt-tounsi.ts.net

The exact hostname is shown in the Lab Guide page.

## Common Issues

### Lab is not visible in Tailscale

Possible causes:

- Lab is not Ready yet.
- Lab expired.
- Tailscale enrollment failed.
- Learner device is not connected to the tailnet.

Resolution:

- Wait until lab status is Running.
- Start a new lab if expired.
- Check learner Tailscale connection.

### SSH connection fails

Possible causes:

- Tailscale is not running locally.
- Wrong hostname.
- Lab ended.
- Lab is still enrolling.

Resolution:

- Run tailscale status.
- Copy the SSH command again from the Lab Guide.
- Wait for Tailscale Enrollment to finish.
- Start a new lab if needed.

### Lab expired

Labs have a fixed 60-minute TTL.

If a lab expires:

- The instance is terminated.
- Data inside the lab is lost.
- The learner must start a new session.

### Learner quota reached

If the learner has too many active labs:

- End one active lab.
- Wait for an active lab to expire.
- Then start a new lab.
