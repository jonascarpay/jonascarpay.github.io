---
title: A Comprehensive Guide to End-to-End-Declarative Deployment with Terraform and Nix
date: 2022-09-19
tags: nix terraform declarative deployment tutorial aws ec2
abstract: Express your entire production pipeline in code; build, provision, and deploy to EC2 with a single command.
...

Introduction
============
This is a guide to declarative nirvana: describing the desired end state of an entire production pipeline (building, provisioning, deploying, and everything in between) in code, and then materializing it with a single command.
We achieve this by integrating two tools: [Terraform](https://www.terraform.io/) and [Nix](https://nixos.org/).

Terraform and Nix are both pieces of software whose success comes from their ability to provide a declarative interface to a procedural world.
In the case of Nix, that world is software, and for Terraform, it's hardware.
Think of them this way and you can see how they fit together to become something greater than the sum of its parts.

We'll be exploring these ideas by building and deploying a simple web service to [Amazon EC2](https://aws.amazon.com/ec2/).
We start with a spartan approach to declarativity: changing a single line of code in the application will invalidate the entire downstream pipeline to the point that our tooling will propose provisioning new hardware.
Once that's done, we'll look at how to tame this into something more ergonomic, while retaining all the benefits.

Preliminaries
-------------
This guide is written as a step-by-step tutorial, one that I've tried to keep approachable for people with limited Terraform or Nix experience.
I try to err on the side of going in too _much_ detail, but Nix and Terraform are both incredibly complex, and there are bound to be details important to you that I thought better to skip or leave implicit.
If you're confused at any point, you can always consult the [end result's source code](https://github.com/jonascarpay/iplz).

Furthermore, if Nix and Terraform are _completely_ new to you, you might want to look at some more basic tutorials first.
For Nix, [Serokell's Practical Nix Flakes](https://serokell.io/blog/practical-nix-flakes) should be a solid starting point, and for Terraform, the [official AWS tutorial](https://learn.hashicorp.com/collections/terraform/aws-get-started) should get you up to speed.

To follow along you only need [Nix](https://nixos.org/download.html#download-nix) installed on your system.
Nix will take care of providing us with a Terraform executable.

I should also mention that we'll be compiling images for x86-64 Linux, so you if you want to follow along you probably want to do so from a x86-64 Linux system, be it natively or from a VM.
It's possible to do cross-compilation with Nix, but a proper treatment of how to do so is outside the scope of this tutorial.

> #### Notes {-}
> Occasionally, at the end of a section, you'll see indented text like this.
> These are notes, which are like footnotes that are too long to go at the bottom.
> They add some extra commentary, but can safely be skipped if you're not interested.
> Here's another:

> #### Nix flakes {-}
> Flakes are an experimental and somewhat controversial new feature of Nix.
> We'll be using flakes to organize all our Nix code in this guide.
> You could argue that it's inappropriate to use flakes for a guide aimed at novices, in which case my counterargument is twofold:
>
> - First, I am a big fan of flakes.
> I think they're simpler and more coherent than "classic" Nix, and tend to recommend beginners to start with Flakes no matter what.
> - More pertinently, I think that flakes' greater emphasis on reproducibility and hermeticity make them especially appropriate here. Any accidental version drift can invalidate the entire infrastructure/pipeline, so the hygiene we get from lock files is invaluable.

Comparisons with other methods
------------------------------
The ideas presented here are not necessarily new, nor is the approach I advocate for the only way of integrating Terraform and Nix.
I do feel, however, that it is the most effective solution out of all the options I know of.
Let's take a second to look at the two most prominent alternatives: NixOps and `terraform-nixos`.

### NixOps

[NixOps](https://github.com/NixOS/nixops) is Nix's "official" cloud deployment system.
It is conceptually similar to Terraform, (and older, actually,) but with a focus on just deploying NixOS.

The biggest problem with NixOps is that, unlike Nix itself, it has a lot of viable alternatives, and the industry has picked Terraform as the de facto [IaC](https://en.wikipedia.org/wiki/Infrastructure_as_code) platform.
NixOps sadly doesn't have the engineering effort behind it that is required to always make it "just work", so if you do use it, you should expect to do a lot of that engineering yourself as soon as you stray from the golden path.

NixOps does of course boast uniquely tight integration with Nix, but as we'll see later, we can actually achieve similar results with Terraform.

### `terraform-nixos`

[`terraform-nixos`](https://github.com/tweag/terraform-nixos) is a Terraform module for managing remote NixOS installations.
It is [recommended on the NixOS website](https://nixos.org/guides/deploying-nixos-using-terraform.html) as _the_ way to deploy NixOS using Terraform.

My main issue with it is that it is too opinionated for how little it actually does:
it is easy to reach a point where you need to tweak its behavior so much that you might as well write something yourself, and when you do, you'll find that it only takes a few dozen lines or so anyway.
So, ultimately, I think it's a better use of your time to just implement all the deployment code yourself from the get-go.

It is also not being maintained as of the time of this writing.

The spartan approach
====================
We'll start by taking the most straightforward path to declarative deployment.
Conceptually, the dependency graph looks like this:

```{ .graphviz }
digraph {
  "Server instance" -> "Server image" -> "NixOS Configuration" -> Application;
}
```

Our server runs an image, the image contains a NixOS configuration, the NixOS configuration contains our application.
Change the application and you invalidate the configuration.
Invalidate the configuration and you invalidate the image.
Invalidate the image and you invalidate the server instance.

In this section, we're working towards the code as it appears on the [`master` branch](https://github.com/jonascarpay/iplz) of the source repository.
We'll start with the Nix side of things, in particular the [`flake.nix`](https://github.com/jonascarpay/iplz/blob/master/flake.nix) file that defines how to build the application and image.
For those following along step-by-step, I recommend using this as your scaffolding, and adding to it as you go along:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    let
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs { inherit system; };

      # Derivations and other expressions go here

    in
    {
      packages.${system} = {
        inherit
          # Outputs go here
          ;
      };
    };
}
```

Writing and building the application
------------------------------------
Our application will be a simple [`icanhazip.com`](http://icanhazip.com) clone called `iplz`.
It simply echoes clients' IP address back at them.

Nix gives you a lot of freedom to write your application and build logic in whatever combination of languages you see fit.
I chose Python just because I figure most people understand it, and the [Falcon web framework](https://falconframework.org/) because it's what I know best, but the choices are arbitrary; it's just a stand-in for a larger application.
If for some reason you actually want to deploy and use this service as-is, you're probably best off just using pure `nginx` with a single `return 200 $remote_addr` directive.

Anyway, this is the business logic in its entirety:

```python
import falcon
import falcon.asgi

class Server:
    async def on_get(self, req, res):
        res.status = falcon.HTTP_200
        res.content_type = falcon.MEDIA_TEXT
        res.text = req.remote_addr + "\n"

app = falcon.asgi.App()
app.add_route("/", Server())
```

The quickest way to turn it into a buildable python package is to stick it in a subdirectory, add a [`setup.py`](https://github.com/jonascarpay/iplz/blob/master/app/setup.py) file, and add these two derivations to `flake.nix`:

```nix
iplz-lib = pkgs.python3Packages.buildPythonPackage {
  name = "iplz";
  src = ./app;
  propagatedBuildInputs = [ pkgs.python3Packages.falcon ];
};

iplz-server = pkgs.writeShellApplication {
  name = "iplz-server";
  runtimeInputs = [ (pkgs.python3.withPackages (p: [ p.uvicorn iplz-lib ])) ];
  text = ''
    uvicorn iplz:app "$@"
  '';
};
```

If you add `iplz-server` to your outputs, you should now be able to run locally with:
```
$ nix run .#iplz-server
...

$ curl localhost:8000
127.0.0.1
```

For reference, the full `flake.nix` file should now look something like this:

```nix
{
  inputs = {
    ...
  };

  outputs = inputs:
    let
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs { inherit system; };

      iplz-lib = pkgs.python3Packages.buildPythonPackage {
        ...
      };

      iplz-server = pkgs.writeShellApplication {
        ...
      };

    in
    {
      packages.${system} = {
        inherit
          iplz-server;
      };
    };
}
```

Defining an image
-----------------
The next step is to turn the application into a deployable image.
Specifically, an image containing a NixOS installation, configured to run `iplz` in the background as a `systemd` service.

Nix has amazing tooling making for building all sorts of images, conveniently collected in [the `nixos-generators` repository](https://github.com/nix-community/nixos-generators).
Because making different images is quick and easy, we'll actually define _two_ images:

1. We'll make a QEMU-based self-contained VM image that we can run locally.
   We use this image to test and debug before deployment.
2. Once that's done, we define the actual EC2 image that will form the basis for our instances.

NixOS is configured through configuration modules, of which we'll have three: one containing the shared base configuration, and then one per image with image-specific configuration.

### Base NixOS configuration {#base-config}

Let's start by writing the base NixOS configuration common between all images.
Here, we simply

- define our application `systemd` service,
- open the required firewall ports,
- set `system.stateVersion`.

```nix
base-config = {
  system.stateVersion = "22.05";
  networking.firewall.allowedTCPPorts = [ 80 ];
  systemd.services.iplz = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    script = ''
      ${iplz-server}/bin/iplz-server --host 0.0.0.0 --port 80
    '';
    serviceConfig = {
      Restart = "always";
      Type = "simple";
    };
  };
};
```

If this were an actual production machine this would be quite bare in terms of user, SSH, and security setup, but for now it will do nicely.

> #### `system.stateVersion` {#stateVersion .unnumbered}
> Without going into too much detail, `system.stateVersion` is supposed to be set to the NixOS release that you first configured a certain machine with, `22.05` at the time of writing.
> It provides a mechanism for NixOS modules to deal with breaking changes when updating, although in practice its actually pretty rare for it to be used.
>
> In this first section of the tutorial, our server gets wiped every time we update/make a new configuration, so technically we don't actually gain anything by setting it.
> Still, it's good practice to set it. Nix will nag at us if we don't, and more importantly, later on we won't be wiping on every configuration change anymore.
> There's some good discussion [here](https://discourse.nixos.org/t/when-should-i-change-system-stateversion/1433) if you're interested.

> #### `networking.firewall` {#firewall .unnumbered}
> NixOS includes a firewall by default.
> We're going to set up EC2 with a firewall as well for reasons we'll see later, so you could technically turn the NixOS one off with `networking.firewall.enable = false` if you don't feel like keeping them in sync.
> I prefer leaving it on.

### QEMU VM {#iplz-vm}

For our QEMU image we add some configuration so that we automatically log in as `root`, plus we open a port so we can connect over HTTP and actually test the service from the host:

```nix
qemu-config = {
  services.getty.autologinUser = "root";
  virtualisation.forwardPorts = [{ from = "host"; host.port = 8000; guest.port = 80; }];
};
```

This is how we turn it into a derivation for an actually runnable QEMU image:

```nix
iplz-vm = inputs.nixos-generators.nixosGenerate {
  inherit pkgs;
  format = "vm";
  modules = [
    base-config
    qemu-config
  ];
};
```

If you add `iplz-vm` to the `flake.nix` outputs, you should now be able to run the VM using:
```
$ nix run .#iplz-vm
```

If all is well, you're now looking at window with a TTY session, and you should be able to `curl` into the VM from the host:
```
$ curl localhost:8000
10.0.2.2
```

### EC2 Image {#iplz-ec2-img}

Now that we have been able to confirm that the NixOS configuration is what we want, it's time to turn it into an EC2-compatible image.
Doing so is easy; just change the `format` attribute from `vm` to `amazon`, and remove the `qemu-config` module.
The only minor annoyance is administrative: the default filename of the image contains a hash, so we add a module (here called `ec2-config`) to manually fix the filename to something more predictable using the `amazonImage.name` option.

```nix
image-name = "iplz";
ec2-config = {
  amazonImage.name = image-name;
};
iplz-ec2-img = inputs.nixos-generators.nixosGenerate {
  inherit pkgs;
  format = "amazon";
  modules = [
    base-config
    ec2-config
  ];
};
iplz-img-path = "${iplz-ec2-img}/${image-name}.vhd";
```

That's it, building `iplz-ec2-img` should now give you an EC2-compatible image in [VHD](https://en.wikipedia.org/wiki/VHD_(file_format)) format.

The Nix-Terraform interface
---------------------------
The next question is how to get our Nix outputs to be Terraform inputs, or as Terraform calls them, variables.
This part is important, because if we get the boundary between Nix and Terraform right, magic happens:
changes in Nix will propagate through to Terraform, where they show up as changes to the variables, and once Terraform sees a change in a variable it will in turn invalidate its downstream resources, giving us what we're here for: end-to-end declarativity.

Variables can be passed to Terraform at run time in several ways, the easiest for us being through environment variables.
If a Terraform module declares a variable `foo`, it will look for the environment variable `TF_VAR_foo`, or in our case, `iplz_img_path` and `TF_VAR_iplz_img_path`, respectively.

There are two ways of setting up environment variables with Nix:

1. Have Nix provide a _shell_ in which the `TF_VAR_foo` variable is set, and run Terraform from that shell.
2. Have Nix provide a _wrapped `terraform` executable_ with the variables already set.

I'm going to use option 2 for the examples for the remainder of this text.
It's a bit more verbose, but also a bit more foolproof.
Ultimately it's personal preference, and there are instructions for both below.
If you choose to go with the shell, replace every instance of `nix run .#terraform` with just a regular `terraform`, and make sure that you're in the deployment shell.

Whatever option you choose, after you've set it up, changing something in the upstream application should invalidate your shell/executable and build a new image.

### Option 1: Shell variable

Define the shell as follows:

```nix
deploy-shell = pkgs.mkShell {
  packages = [ pkgs.terraform ];
  TF_VAR_iplz_img_path = iplz-img-path;
};
```

In your `flake.nix`, add this to your flake output attributes, so on the same level as `packages.${system}`:
```nix
devShell.${system} = deploy-shell;
```

You can now enter the shell using `nix develop`:

```
$ nix develop
(nix-shell) $ echo $TF_VAR_iplz_img_path
/nix/store/wz4f6yypxrwxn3glqxi73rd9xdyp12gq-iplz-x86_64-linux/iplz-x86_64-linux.vhd
```

### Option 2: Wrapped executable

Define the executable as follows:
```nix
terraform = pkgs.writeShellScriptBin "terraform" ''
  export TF_VAR_iplz_img_path="${iplz-img-path}"
  ${pkgs.terraform}/bin/terraform $@
'';
```

Now add `terraform` to your outputs under `packages.${system}`.
You should now be able to execute the wrapped Terraform with:

```
$ nix run .#terraform -- version
Terraform v1.2.7
on linux_amd64
```

Terraform Setup
---------------
To recap, we now have the ability of launching Terraform in an environment where the `iplz_img_path` variable points at an image containing our application, and that path changes automatically when our application changes.
On the Terraform side, we just need to write a module declaring the necessary resources, and we're ready to deploy.

Under normal circumstances, launching an EC2 instance with Terraform takes just one or two resource declarations.
In our case however, it's made quite a bit more difficult by the fact that during the instantiation process, we want to get an image from our disk and into AWS in such a way that we can boot an instance from it, for which there is no first-class support.
So, we need to add some plumbing.

The Terraform pipeline fundamentally consists of uploading our EC2 image to an [`aws_s3_bucket`](#aws_s3_bucket) with [`aws_s3_object`](#aws_s3_object), turning it into an EBS snapshot with [`aws_ebs_snapshot_import`](#aws_ebs_snapshot_import), passing the snapshot volume to actual AMI with [`aws_ami`](#aws_ami), and passing that AMI in turn to our final [`aws_instance`](#aws_instance).
All the other resources are boilerplate, mostly just to get the right permissions in place.

The full final dependency graph looks like this:

```{ .graphviz }
digraph {
  node [shape="box"];
  public_ip [shape="invhouse"];
  iplz_img_path [shape="house"];

  public_ip -> aws_instance;
  aws_instance -> aws_ami;
  aws_s3_bucket_acl -> aws_s3_bucket;
  aws_instance -> aws_security_group;
  aws_ami -> aws_ebs_snapshot_import;
  aws_ebs_snapshot_import -> aws_iam_role;
  aws_ebs_snapshot_import -> aws_s3_object;
  aws_iam_role_policy_attachment -> aws_iam_policy;
  aws_iam_role_policy_attachment -> aws_iam_role;
  aws_iam_policy -> aws_s3_bucket;
  aws_s3_object -> iplz_img_path;
  aws_s3_object -> aws_s3_bucket;
}
```

The main takeaway of this section is that with the setup described in this graph, we can declaratively upload disk images and boot instances with them.
Once you have the high-level picture, the implementation details can mostly be figured out from the Terraform docs.
I'll still go over the individual resources and briefly explain what they do in the next section, but the point is that there is nothing particularly surprising or interesting about the individual resources.
The full Terraform source file can be found [here](https://github.com/jonascarpay/iplz/blob/master/main.tf).

### Terraform resources

As promised, I will outline the individual resources and briefly comment on them.
Their titles link to the corresponding Terraform documentation page.

#### [`aws_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
This is the final EC2 instance, the thing that everything else is here to enable.
Terraform and AWS disagree about the default security group behavior, so we explicitly define one.
In fact, I find that with Terraform it's often best to be explicit.
Other than that, there's not much here:
```nix
resource "aws_instance" "iplz_server" {
  ami                    = aws_ami.iplz_ami.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.iplz_security_group.id]
}
```

#### [`aws_security_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
A security group describes a set of connectivity rules.
We only need TCP port 80 for now, but if you're already using the [NixOS firewall](#firewall) you could also leave this completely open.
Either way, Terraform and AWS seem to disagree about what the default settings are, so it's safest to be explicit here.

```nix
resource "aws_security_group" "iplz_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

#### [`aws_ami`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ami)
An AMI is an Amazon Machine Image, which is the final image that we actually boot our instance with.
AMIs are higher level images than the EC2 images we've been making.
They can contain multiple disks, plus some extra metadata.
The way we make an AMI out of our custom image is by passing turning it into the hard drive volume that our AMI boots from, which we do [below](#aws_ebs_snapshot_import).

The EC2 module in Nix [only works with `hvm`](https://github.com/NixOS/nixpkgs/blob/b207142dcc285f985ae6419df914262debeef12a/nixos/modules/virtualisation/amazon-image.nix#L35) here, so there's no question about what virtualization type to use.

```nix
resource "aws_ami" "iplz_ami" {
  name                = "iplz_server_ami"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ebs_block_device {
    device_name = "/dev/xvda"
    snapshot_id = aws_ebs_snapshot_import.iplz_import.id
  }
}
```

#### [`aws_ebs_snapshot_import`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_snapshot_import)

An EBS volume can be thought of as a virtual hard disk.
In this step we turn our VHD image into such a volume[^grahamc].

The resulting volume won't automatically invalidate when the image changes, so we manually add a trigger for it.
Also, importing a VM on AWS [requires special permissions](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html#vmimport-role), so we define [a special role for it below](#aws_iam_role).
```nix
resource "aws_ebs_snapshot_import" "iplz_import" {
  role_name = aws_iam_role.vmimport_role.id
  disk_container {
    format = "VHD"
    user_bucket {
      s3_bucket = aws_s3_bucket.iplz_bucket.id
      s3_key    = aws_s3_object.image_upload.id
    }
  }
  lifecycle {
    replace_triggered_by = [
      aws_s3_object.image_upload
    ]
  }
}
```

[^grahamc]:
`aws_ebs_snapshot_import` was actually [made by `grahamc`](https://github.com/hashicorp/terraform-provider-aws/pull/16373), a prominent member of the Nix community.
I don't think that's a coincidence, but I'm not actually sure.

#### [`aws_iam_role`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role), [`aws_iam_policy`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy), and [`aws_iam_role_policy_attachment`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) {#aws_iam_role}

The end goal with these three resources is to run [`aws_ebs_snapshot_import`](#aws_ebs_snapshot_import) with the permissions required to import a VM snapshot.
AWS IAM (Identity and Access Management) is an extremely complex topic in and of itself, and the Terraform interface to it doesn't always actually make it easier.
What we need to do here is to capture the [service role configuration described here](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html#vmimport-role) in Terraform resources.
At the time of writing, the recommended way of doing that is by putting the role configuration in an `aws_iam_role`, the policy configuration in an `aws_iam_policy`, and then attaching the policy to the role with an `iam_role_policy_attachment`.

I've omitted most of the actual policies, since they're just copied verbatim from the previous link.
The exception is that by going through Terraform, we can use string interpolation to refer to our other resources inside the policies, as seen in `vmimport_policy`.

```nix
resource "aws_iam_role_policy_attachment" "vmpimport_attach" {
  role       = aws_iam_role.vmimport_role.id
  policy_arn = aws_iam_policy.vmimport_policy.arn
}

resource "aws_iam_role" "vmimport_role" {
  assume_role_policy = jsonencode({
    ...
  })
}

resource "aws_iam_policy" "vmimport_policy" {
  policy = jsonencode({
    ...
      Resource = [
        "arn:aws:s3:::${aws_s3_bucket.iplz_bucket.id}",
        "arn:aws:s3:::${aws_s3_bucket.iplz_bucket.id}/*"
      ]
    ...
  })
}
```

#### [`aws_s3_bucket`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)
An S3 bucket.
Access control configuration is handled by [`aws_s3_bucket_acl`](#aws_s3_bucket_acl), uploading is handled by [`aws_s3_object`](#aws_s3_object), leaving no configuration to go here.
```nix
resource "aws_s3_bucket" "iplz_bucket" {}
```

#### [`aws_s3_bucket_acl`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl)
The bucket's [access control list](https://docs.aws.amazon.com/AmazonS3/latest/userguide/acl-overview.html).
ACLs are a mess, but `"private"` should be fine for most purposes.
```nix
resource "aws_s3_bucket_acl" "iplz_acl" {
  bucket = aws_s3_bucket.iplz_bucket.id
  acl    = "private"
}
```

#### [`aws_s3_object`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object)
Facilitates the uploading of the VHD to S3.
```nix
resource "aws_s3_object" "image_upload" {
  bucket = aws_s3_bucket.iplz_bucket.id
  key    = "iplz.vhd"
  source = var.iplz_img_path
}
```


Deployment
----------

First, if you haven't already,

1. Make sure you [set up AWS authentication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration).
   You can set it up through Terraform, or in any one of the many ways supported by `aws-cli`.
2. Initialize Terraform with `nix run .#terraform init`.

Confirm that you're ready to deploy by looking at the execution plan.
It should look a lot like this:

```console
$ nix run .#terraform plan
Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  ...
  + resource "aws_ami" "iplz_ami" { ... }
  + resource "aws_ebs_snapshot_import" "iplz_import" { ... }
  + resource "aws_iam_policy" "vmimport_policy" { ... }
  + resource "aws_iam_role" "vmimport_role" { ... }
  + resource "aws_iam_role_policy_attachment" "vmimport_attach" { ... }
  + resource "aws_instance" "iplz_server" { ... }
  + resource "aws_s3_bucket" "iplz_bucket" { ... }
  + resource "aws_s3_bucket_acl" "iplz_acl" { ... }
  + resource "aws_s3_object" "image_upload" { ... }
  + resource "aws_security_group" "iplz_security_group" { ... }

Plan: 10 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + public_ip = (known after apply)
```

If all of that looks in order, you are ready to set things in motion:
```console
$ nix run .#terraform apply
...
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
...
```

After waiting for deployment to finish and giving the server some time too boot up, you should now be able to query it and get back your public IP:

```console
$ curl $(nix run .#terraform -- output -raw public_ip)
12.34.56.78
```

It took some effort, but we were finally able to deliver on the promise of building, provisioning, and deploying with a single command!
Don't forget to `nix run .#terraform destroy` after you're done.
Depending on your plan you might get charged if you accidentally leave your server running.

### Redeployment

At this point, it's a good exercise to see what happens if you change the application.
Any change works, for example, having the response be `"Your IP is <ip>"`.

Now, running `nix run .#terraform apply` should first rebuild the disk image, and then present you with a list of changes:

```console
$ nix run .#terraform apply
Terraform will perform the following actions:
-/+ resource "aws_ami" "iplz_ami" { ... }
-/+ resource "aws_ebs_snapshot_import" "iplz_import" { ... }
-/+ resource "aws_instance" "iplz_server" { ... }
  ~ resource "aws_s3_object" "image_upload" { ... }
Plan: 3 to add, 1 to change, 3 to destroy.
```

Annoyingly, it will instantiate an entirely new server, with a new IP address and everything, even for a minor change such as this.
That's what we'll be tackling in the next section.

Improving the ergonomics
========================

To reiterate, the main issue with the approach we've used so far is how aggressively it re-provisions hardware.
If your application is stable that might be fine, but there are many situations where this is not ideal.
Maybe you don't want to wait for provisioning every time you change something, maybe you have other things running on the server that cannot be shut down, or maybe you can't afford to get a new IP address after every change; whatever the reason, it can be impractical to tie the lifetime of your server to that of the application this tightly.
In this section, we look at how to mitigate this problem.

The core issue is the impedance mismatch between the `aws_instance` resource and the application.
The application can change frequently, but the instance is happiest when it is set up once and then forgotten about[^amazon].
The solution is conceptually pretty simple: make it so that the server instance doesn't depend on the application anymore.
We do this is by adding a layer of indirection:

[^amazon]: Coincidentally, this is also when Amazon is happiest.

```{ .graphviz }
digraph {
  "NixOS deployment" -> "Server instance" -> "Server bootstrap image" -> "NixOS bootstrap configuration";
  "NixOS deployment" -> "NixOS live configuration" -> "Application";
}
```

This change can best be understood as splitting our NixOS configuration in two: the _bootstrap_ configuration, and the _live_ configuration.

- The bootstrap configuration is the smallest possible configuration that gives us a NixOS installation with SSH access. The server instance depends on this, so it should ideally never change after provisioning.
- The live configuration is what contains our actual application. This is the part that we want to be able to change however often and whenever and we want.

We unify the server instance and the live configuration running on it with a pseudo-resource, called the _deployment_ in the above graph.
With this setup, any changes to the application only invalidate the right-hand side of the dependency graph.
Along the way, we'll also make it so we won't need to copy multiple gigabytes to our server every time we make a small change.

A quick note before we continue: this section spends like 2000 words explaining what is ultimately only about a 50 line change in the actual codebase.
My goal is to carefully explain the reasoning, but I also think it's valuable to maintain a sense of proportion.
If you want to jump straight to the end result, you can find it on the [`faster-deployment` branch](https://github.com/jonascarpay/iplz/tree/faster-deployment).

Splitting the NixOS configuration
---------------------------------
In this section we split our NixOS configuration into the bootstrap and live configurations we defined above.
NixOS uses the word "configuration" pretty loosely to refer to a system configuration's entire life cycle.
The thing you write, build, activate, and boot are all "the configuration".
For the purposes of this section, configuration means two things, each handled in its own subsection:

- The configuration _description_ refers to the specification of NixOS options.
An example would be the [`base-config` module above](#base-config), but more generally it refers to all the modules that you pass to a builder.
- The configuration _derivation_ is the thing that we build; the result of turning the description into an actual buildable artifact. So far, we've had two of these, the [`iplz-vm`](#iplz-vm) and the [`iplz-ec2-img` image](#iplz-ec2-img) images, and we'll soon add a "naked" NixOS configuration derivation.

### Splitting the configuration description

This part is simple. Looking at our [base NixOS configuration module above](#base-config), you can see that with the exception of the `system.stateVersion` option[^stateVersion], everything here is application-specific.
In other words, if you remove those application-specific parts, you're left with this perfectly usable bootstrap configuration:

[^stateVersion]: As alluded to [above](#stateVersion), this is where `sytem.stateVersion` actually starts to matter.

```nix
bootstrap-config-module = {
  system.stateVersion = "22.05";
};
```

The only thing to add is SSH access, so that we can actually talk to our server after instantiation.
Setting `services.openssh.enable` automatically opens port 22, so you don't need to touch the firewall configuration.
The complete bootstrap configuration module looks like this:

```nix
bootstrap-config-module = {
  system.stateVersion = "22.05";
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    <public keys>
  ];
};
```

The live configuration module is then just the base configuration module minus `system.stateVersion`:

```nix
live-config-module = {
  networking.firewall.allowedTCPPorts = [ 80 ];
  systemd.services.iplz = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    script = ''
      ${iplz-server}/bin/iplz-server --host 0.0.0.0 --port 80
    '';
    serviceConfig = {
      Restart = "always";
      Type = "simple";
    };
  };
};
```

> #### `cloud-init` and SSH Access {-}
>
> If you make a system using `nixos-generators` the way we have so far, the NixOS configuration will contain [`cloud-init`](https://github.com/canonical/cloud-init).
> `cloud-init` is a standard interface for the initialization of OSes on cloud machines.
> Among other things, `cloud-init` provides a way to configure a machine with SSH keys.
> Terraform exposes this through the `aws_instance` resource's [`key_name` argument](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance#key_name).
>
> As shown above, NixOS already provides a way to manage SSH keys by just putting them in the configuration.
> That means you have a choice here of how you want to set up your keys: through Nix or through Terraform.
> I find it's easier to just do it in NixOS, but you can choose either one, just make sure you're not accidentally using both.

### Splitting the configuration derivation

This next part is going to be slightly trickier. The bootstrap configuration will still be distributed as an EC2-compatible VHD image, which now simply looks like this:

```nix
bootstrap-img = inputs.nixos-generators.nixosGenerate {
  inherit pkgs;
  format = "amazon";
  modules = [
    bootstrap-config-module
    { amazonImage.name = bootstrap-img-name; }
  ];
};
```

When we push the live configuration to the server however, we don't want to copy it as an image, we want to just copy over the image's _contents_, the naked underlying NixOS configuration.
Getting the derivation for those contents is a bit finicky, since it's not designed to be done manually.
It's usually taken care of automatically by `nixos-rebuild` (if you're on NixOS) or `nixos-generators` (if you're making an image, as we've been doing up until now).
Here's what that looks like:

```nix
live-config = (inputs.nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    bootstrap-config-module
    live-config-module
    "${inputs.nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
  ];
}).config.system.build.toplevel;
```

Other than that we've added `live-config-module` there are basically just two changes here compared to how we built the AMI previously:

1. Instead of using `nixosGenerate`, we use `lib.nixosSystem`, and then navigate to the `.config.system.build.toplevel` attribute of the result.

2. We manually include the module containing EC2 compatibility settings.

If you change `toplevel` to `amazonImage`, you've actually completely replicated the `nixosGenerate` functionality, and you're back to building an AMI.
If you've come this far, it's actually worth considering dropping `nixos-generators` altogether, and manually implementing the same functionality.
You gain some transparency, if you wrap it nicely you don't sacrifice readability, and it's good practice with NixOS nuts and bolts.
At the very least, I recommend studying the `nixos-generators` source code, since it doesn't actually do that much.

Anyway, with the bootstrap image and live configuration defined, we can pass them to Terraform as input variables.
So, if you're using a shell:
```nix
deploy-shell = pkgs.mkShell {
  packages = [ pkgs.terraform ];
  TF_VAR_bootstrap_img_path = bootstrap-img-path;
  TF_VAR_live_config_path = "${live-config}";
};
```
And if you're using a wrapped executable:
```nix
terraform = pkgs.writeShellScriptBin "terraform" ''
  export TF_VAR_bootstrap_img_path="${bootstrap-img-path}"
  export TF_VAR_live_config_path="${live-config}"
  ${pkgs.terraform}/bin/terraform $@
'';
```

Remember to also update the variable declarations in the Terraform configuration.

Creating the deployment resource
--------------------------------
Switching a remote server to a new NixOS configuration, operationally, requires two steps: uploading the configuration, and then activating it.
Our goal here is to capture this process in a Terraform resource, such that it happens automatically whenever our configuration changes.
There's also a few smaller tweaks and workarounds we need, mostly just to make everything SSH-based run smoothly.

### Implementing the resource
#### The Nix side
You copy Nix paths from one computer to another with `nix-copy-closure`.
From [the `man` page](https://nixos.org/manual/nix/unstable/command-ref/nix-copy-closure.html):

> `nix-copy-closure` gives you an easy and efficient way to exchange software between machines.
> Given one or more Nix store paths on the local machine, `nix-copy-closure` computes the closure of those paths (i.e. all their dependencies in the Nix store), and copies all paths in the closure to the remote machine via the ssh (Secure Shell) command.

This is exactly what we need, and has the additional benefit of only ever copying the parts of the configuration that have changed.

Once the configuration has been copied, we SSH into the instance, and call the `switch_to_configuration` script in the configuration root.
We'll also run garbage collection afterwards, since for the purposes of this guide, at least, this is the only time we'll ever create garbage.

> ##### `nixos-rebuild` {-}
> This way of copying and activating is exactly what `nixos-rebuild` does when you pass the `--target` flag.
> The interface to `nixos-rebuild` unfortunately doesn't allow us to use it directly, so we have to emulate it.
> If you want to know more about what it does, it's an ordinary bash script so if you're on NixOS you can simply run `cat $(which nixos-rebuild)` to inspect its contents.

#### The Terraform side
Now, we just need to capture this upload-and-activate workflow in a Terraform resource.

Every Terraform resource supports running custom actions after they've been instantiated.
These actions called [_provisioners_](https://www.terraform.io/language/resources/provisioners/syntax), and they are our entry point for inserting custom logic.
In this case, the pseudo-resource we've been describing is a resource that consists _only_ of provisioners, which is precisely what [Terraform's `null_resource`](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) is for.
By setting the null resource's trigger to `live_config_path`, it will run every time the live configuration changes, and because in this case it depends on the server instance's `public_ip` attribute, that will only ever happen _after_ provisioning.

Putting it all together looks like this:

```nix
resource "null_resource" "nixos_deployment" {
  triggers = {
    live_config_path = var.live_config_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      nix-copy-closure $TARGET ${var.live_config_path}
      ssh $TARGET '${var.live_config_path}/bin/switch-to-configuration switch && nix-collect-garbage -d'
      EOT
    environment = {
      TARGET = "root@${aws_instance.iplz_server.public_ip}"
    }
  }
}
```

### SSH ingress rule
In order to get SSH access to our instance, we also need to define a new `ingress` rule for port 22, in the same way as we opened port 80 for HTTP traffic.
Just duplicate [the `ingress` block](#aws_security_group) and change the port number.

### Timing issues
If you run `terraform apply` in its current state, you'll find that the null resource fails with an SSH timeout.
The issue is that Terraform will wait until the instance is _provisioned_, but not until it's actually _booted_.
This is a common issue, and fortunately there's a pretty simple workaround: we simply add a `remote_exec` provisioner to the instance that immediately returns.
`remote_exec` will automatically retry until SSH is up, thereby delaying downstream resources until SSH works.

```nix
resource "aws_instance" "iplz_server" {
  ...
  provisioner "remote-exec" {
    connection {
      host = self.public_ip
      private_key = file("~/.ssh/id_ed25519") # <- Change this
    }
    inline = [ "echo 'SSH confirmed!'" ]
  }
}
```

### Automatically adding the instance to `known_hosts`
The final issue with SSH access is that when `nix-copy-closure` connects to the instance, SSH will give the usual prompt asking the user to confirm that the target is a trusted machine.
The interactive prompt doesn't play nice with Terraform, and even if it did, it's annoying, so let's remove it.
As far as I know the most robust way to do so is to first add the server to `~/.ssh/known_hosts` using a `local_exec` provisioner in the `aws_instance`:

```nix
resource "aws_instance" "iplz_server" {
  ...
  provisioner "local-exec" {
    command = "ssh-keyscan ${self.public_ip} >> ~/.ssh/known_hosts"
  }
}
```

Deployment
----------

Deployment itself should look similar to how it did before.
It's done in the exact same way, it will just take some extra time to wait until SSH is up so it can deploy the live configuration.

The gains we've made become much more apparent when redeploying, however.
If you change your application and run `nix run .#terraform apply`, it should now look something like this:

```
  # null_resource.nixos_deployment must be replaced
-/+ resource "null_resource" "nixos_deployment" { ... }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Compared to [before](#redeployment), this only touches the `nixos_deployment` resource, applying should take significantly less time, and it all leaves the instance itself in place.

Again, the final resulting source code can be found on the [`faster-deployment` branch](https://github.com/jonascarpay/iplz/tree/faster-deployment), and as always, don't forget to run `terraform destroy` afterwards.

Final thoughts
==============

Where to go from here
---------------------

If you've made it this far, here are some suggestions for how to continue the development of your deployment pipeline and turn it into something production-worthy.
Some of these are simple tips and tricks, some of these are stubs for what would really deserve its own blog post but serve to at least point you in the right direction.

### Removing the remaining sources of invalidation
We have made it easy to make changes by making the live configuration lightweight, but it's still possible to unintentionally change the bootstrap configuration and thereby invalidate the instance.
One example of this is when you update `nixpkgs`: the bootstrap configuration depends on `nixpkgs`, so Terraform will see that the bootstrap configuration has changed, which invalidates every instance that was created with that configuration.
This is extra irritating because once you have a live configuration up and running, the bootstrap configuration doesn't actually have any bearing on the running instance anymore.

In the specific case above you could mitigate this by using separate `nixpkgs` inputs for the bootstrap and live configurations, but doesn't really address the underlying issue, and doesn't completely protect you from accidental invalidation.
My preferred solution is to actually make the instance completely ignore all changes to its inputs once provisioned:

```nix
resource "aws_instance" "iplz_server" {
  ...
  lifecycle {
    ignore_changes = all
  }
}
```
You could be more granular and explicit here by [giving a list of inputs to ignore](https://www.terraform.io/language/meta-arguments/lifecycle), but in this case just using `all` is fine too.

If you don't want to deal with managing your own bootstrap image, you can also consider completely dropping it altogether.
The [AMI Catalog](https://us-east-1.console.aws.amazon.com/ec2/v2/home?region=us-east-1#AMICatalog:) contains many ready-to-run NixOS AMIs that you can use instead of the bootstrap image.
Just set up SSH access through Terraform, and update the live configuration as normal.
This saves you the trouble of setting up an S3 bucket just to bootstrap your server, and after the live configuration has been uploaded you won't be able to tell the difference.

Personally, I like the control that having my own image provides, but both approaches are valid.

### Have Nix manage Terraform providers
You could argue that we're not completely declarative because we have to install Terraform providers with `terraform init` before we can actually use it.
Luckily, Nix can actually declaratively manage our providers for us.

Instead of `pkgs.terraform`, just use `(pkgs.terraform.withPlugins (p: [ p.aws p.null ]))`.
You'll still need to run `terraform init`, but it won't install anything anymore, and in fact you could even add the resulting files to version control.

Unfortunately, at the time of writing there are some issues with the `null` provider that make going through Terraform as normal the more robust option, but if you try it and it works for your particular setup, there's no reason not to use it.

### Secret management
Declarative configuration is often at odds with proper secret management.
This is doubly so with Nix, where everything Nix touches ends up publicly readable in the Nix store.
I don't have any universal recommendations here, because it all depends on your threat model and attack vectors.

In general, Terraform is better equipped for dealing with secrets than Nix, so if you can go through Terraform that's usually the better option.
You can use provisioners to upload sensitive files and automatically interface with your secret management setup.

### Disk sizing
With the above setup, your instance will have a single hard drive, whose size is simply the size of the EC2 image.
That's not ideal, because it's not a very large image, and what little space there is is shared by both the NixOS configuration and application data.
You could just create a larger disk image, but it's probably a better idea to separate your data drive from your OS drive by creating separate EBS volumes.
That way you can scale them independently as you see fit.

### Terraform best practices
All the Terraform source code is currently in a single `main.tf` file.
I decided on this to keep the guide simple, but it does go against [Terraform's module structure conventions](https://www.terraform.io/language/modules/develop/structure).
If you use this as the basis of a more serious project you probably want to consider reorganizing the Terraform code.

### Scaling up and modularizing
One question you might have is how to extend this approach to multiple instances.
The answer is actually the same way you duplicate any part of Terraform configuration: you use a [`count`](https://www.terraform.io/language/meta-arguments/count) or [`for_each`](https://www.terraform.io/language/meta-arguments/for_each) clause.

In the case of the spartan approach, you can just slap a `count` on the `aws_instance` resource directly.
For the more ergonomic approach, things are slightly trickier since you need to duplicate the `nixos_deployment` resource in tandem.
You do that by collecting the parts that need to be duplicated together in a [_module_](https://www.terraform.io/language/modules/develop), and then putting the `count`/`for_each` clause on the module call.

### Inverting the dependency
In the current workflow, Nix precedes Terraform, in the sense that Nix prepares all variables before Terraform runs and uses them.

You could invert this dependency by having Terraform call Nix as part of `terraform apply` through null resources, similar to how [`terraform-nixos`](#terraform-nixos) works.
This is obviously a bit trickier to set up, but it would give the interesting ability to make _derivations that depend on Terraform resources_.

One idea that comes to mind is to use instances' public keys after they've been provisioned, for example to grant them access to downstream resources, or to use an [`agenix`](https://github.com/ryantm/agenix)-based secret management workflow.

### Mixing the two approaches
There's nothing that says you can't use both the spartan and ergonomic approaches in the same deployment.

For example, maybe you use Terraform to manage both testing and production environments.
In that case, maybe your testing environment consists of a few machines that can easily be updated, but your production environment consists of many stateless auto-scaling machines, where the rigidity of the fixed-configuration image is actually kind of nice.

Ideally, you'd do this in a way where Nix can make different artifacts for different branches, but if necessary you can always manually control deployments with [target resources](https://learn.hashicorp.com/tutorials/terraform/resource-targeting).

Conclusion
----------

And with that, we're done.
It's undeniably hairy in a few places, but first of all, what isn't, and second, I think it's easily worth it: we now have fast, efficient, end-to-end-declarative deployments.

If you've made it this far, thank you very much for reading.
If you have any comments/questions/suggestions/feedback, or maybe you just found this guide useful and want to let me know, feel free to reach out by sending an email or opening a GitHub issue.

Thanks to [Dennis Gosnell](https://functor.tokyo/) and [Viktor Kronvall](https://github.com/considerate/) for their feedback while writing this post.
