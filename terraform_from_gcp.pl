#!/usr/bin/env perl

use strict;
use warnings;

# https://cloud.google.com/sdk/gcloud/reference/topic/projections

{
    package TerraformFromGCP;
    
    my @PACKAGES = qw(
        GoogleComputeNetwork
        GoogleComputeSubnetwork
        GoogleComputeFirewall
        GoogleComputeDisk
        GoogleComputeInstance
    );

    our $GCLOUD_CMD = 'gcloud';
    
    sub MAIN
    {
        my @argv = @_;

        environment();

        my @buf;
        foreach my $p (@PACKAGES) {
            push(@buf, $p->run());
        }
        print join("\n", @buf);
        return 0;
    }

    sub environment
    {
        if (exists $ENV{GCLOUD_CMD} and 0 < length($ENV{GCLOUD_CMD})) {
            $GCLOUD_CMD = $ENV{GCLOUD_CMD};
        }
    }
    
    exit MAIN(@ARGV);
}

{
    package TerraformResource;

    sub list_cmd {}
    sub resource_name {}
    sub template_for_oneline {}

    sub run
    {
        my $self = shift(@_);
        my $names = $self->load_list();
        return $self->to_string($names);
    }

    sub load_list
    {
        my $self = shift(@_);
        my $list_cmd = $self->list_cmd();
        my @lines = `$list_cmd`;
        my @params;
        shift(@lines);
        foreach my $line (@lines) {
            chomp($line);
            my @ts = split(/\s+/, $line);
            push(@params, \@ts);
        }
        return \@params;
    }

    sub to_string
    {
        my $self = shift(@_);
        my ($params) = @_;
        my @buf;
        foreach my $param (@$params) {
            push(@buf, $self->template_for_oneline($param));
        }
        return join("\n", @buf);
    }
}

{
    package TerraformResourceWithName;
    use base qw/TerraformResource/;

    sub template_for_oneline
    {
        my $self = shift(@_);
        my ($param) = @_;
        my ($name) = @$param;
        my $resource_name = $self->resource_name();
        return <<EOL;
# terraform import $resource_name.$name $name
resource "$resource_name" "$name" {
  name = "$name"
}
EOL
    }
}

{
    package GoogleComputeNetwork;
    use base qw/TerraformResourceWithName/;
    sub list_cmd { qq|$TerraformFromGCP::GCLOUD_CMD compute networks list| };
    sub resource_name { 'google_compute_network' };
}

{
    package GoogleComputeSubnetwork;
    use base qw/TerraformResource/;
    sub list_cmd { qq|$TerraformFromGCP::GCLOUD_CMD compute networks subnets list| };
    sub resource_name { 'google_compute_subnetwork' };

    sub template_for_oneline
    {
        my $self = shift(@_);
        my ($param) = @_;
        my ($name, $network, $cidr) = @{$param}[0, 2, 3];
        my $resource_name = $self->resource_name();
        return <<EOL;
# terraform import $resource_name.$name $name
resource "$resource_name" "$name" {
  name = "$name"
  network = "$network"
  ip_cidr_range = "$cidr"
}
EOL
    }
}

{
    package GoogleComputeFirewall;
    use base qw/TerraformResource/;
    sub list_cmd { qq|$TerraformFromGCP::GCLOUD_CMD compute firewall-rules list --format="table(name,network,direction,priority,sourceRanges.list():label=SRC_RANGES,allowed[].map().firewall_rule().list():label=ALLOW,disabled,targetTags.list():label=TARGET_TAGS,destinationRanges.list():label=DEST_RANGES,denied[].map().firewall_rule().list():label=DENY,sourceTags.list():label=SRC_TAGS,sourceServiceAccounts.list():label=SRC_SVC_ACCT,targetServiceAccounts.list():label=TARGET_SVC_ACCT)"| };
    sub resource_name { 'google_compute_firewall' };

    sub template_for_oneline
    {
        my $self = shift(@_);
        my ($param) = @_;
        #NAME                    NETWORK  DIRECTION  PRIORITY  SRC_RANGES       ALLOW                         DISABLED  TARGET_TAGS  DEST_RANGES  DENY  SRC_TAGS  SRC_SVC_ACCT  TARGET_SVC_ACCT
        #allow-from-ug           default  INGRESS    1000      202.221.220.251  tcp:22                        False     server-ug
        #default-allow-icmp      default  INGRESS    65534     0.0.0.0/0        icmp                          False
        #default-allow-internal  default  INGRESS    65534     10.128.0.0/9     tcp:0-65535,udp:0-65535,icmp  False
        #default-allow-rdp       default  INGRESS    65534     0.0.0.0/0        tcp:3389                      True
        #default-allow-ssh       default  INGRESS    65534     0.0.0.0/0        tcp:22                        True
        my ($name, $network, $priority, $src, $rule_expr, $disabled, $tags) = @{$param}[0, 1, 3, 4, 5, 6, 7];
        my $resource_name = $self->resource_name();
        $disabled = lc($disabled);
        my $rule_string = $self->make_rule_string($rule_expr);
        my @append_opts = ($rule_string);
        if (defined($tags)) {
            push(@append_opts, $self->make_target_tags($tags));
        }
        my $opt = join("\n", @append_opts);
        chomp($opt);
        return <<EOL;
# terraform import $resource_name.$name $name
resource "$resource_name" "$name" {
  name = "$name"
  network = "$network"
  priority = "$priority"
  disabled = $disabled

$opt
}
EOL
    }

    sub make_rule_string
    {
        my $self = shift(@_);
        my ($rule_expr) = @_;
        my @rules = split(/,/, $rule_expr);
        my @rule_strings;
        foreach my $r (@rules) {
            if ($r =~ m/:/) {
                my ($protocol, $port) = split(/:/, $r);
                push(@rule_strings, <<EOL);
  allow {
    protocol = "$protocol"
    ports = ["$port"]
  }
EOL
            } else {
                push(@rule_strings, <<EOL);
  allow {
    protocol = "$r"
  }
EOL
            }
        }
        return join("\n", @rule_strings);
    }

    sub make_target_tags
    {
        my $self = shift(@_);
        my ($tags) = @_;
        return <<EOL;
  target_tags = ["$tags"]
EOL
    }
}

{
    package GoogleComputeDisk;
    use base qw/TerraformResource/;
    sub list_cmd { qq|$TerraformFromGCP::GCLOUD_CMD compute disks list --format="table(name,zone,size_gb,type,source_image.basename(),status)"| };
    sub resource_name { 'google_compute_disk' };

    sub template_for_oneline
    {
        my $self = shift(@_);
        my ($param) = @_;
        #NAME        ZONE               SIZE_GB  TYPE    SOURCE_IMAGE        STATUS
        #instance-1  asia-northeast1-b  20       pd-ssd  centos-7-v20190213  READY
        my ($name, $zone, $size, $type, $source_image, $status) = @{$param};
        my $resource_name = $self->resource_name();
        return <<EOL;
# terraform import $resource_name.$name $name
resource "$resource_name" "$name" {
  name = "$name"
  zone = "$zone"
  type = "$type"
  size = $size
  image = "$source_image"
}
EOL
    }
}

{
    package GoogleComputeInstance;
    use base qw/TerraformResource/;
    sub list_cmd { qq|$TerraformFromGCP::GCLOUD_CMD compute instances list --format="table(name,zone.basename(),machineType.machine_type().basename(),networkInterfaces[].networkIP.notnull().list():label=INTERNAL_IP,networkInterfaces[].accessConfigs[0].natIP.notnull().list():label=EXTERNAL_IP,status,serviceAccounts[0].scopes.join(','),disks.filter('boot:true').firstof(deviceName).join(','),networkInterfaces[0].network.basename(),networkInterfaces[0].subnetwork.basename(),tags.items.join(','):label=TAGS)"| };
    sub resource_name { 'google_compute_instance' };

    sub template_for_oneline
    {
        my $self = shift(@_);
        my ($param) = @_;
        #NAME        ZONE               MACHINE_TYPE  INTERNAL_IP  EXTERNAL_IP  STATUS      SCOPES                                                                                                                                                                                                                                                                                                       DISKS       NETWORK  SUBNETWORK  TAGS
        #instance-1  asia-northeast1-b  f1-micro      10.146.0.2   35.213.6.71  TERMINATED  https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append  instance-1  default  default     server-ug
        my ($name, $zone, $type, $in_ip, $ex_ip, $status, $scopes, $boot_disk, $network, $subnetwork, $tags) = @{$param};
        my $resource_name = $self->resource_name();
        my @opts;
        push(@opts, $self->make_tag_string($tags));
        push(@opts, $self->make_scope_string($scopes));
        my $opt_str = join("\n", @opts);
        chomp($opt_str);
        return <<EOL;
# terraform import $resource_name.$name $name
resource "$resource_name" "$name" {
  name = "$name"
  zone = "$zone"
  machine_type = "$type"

  boot_disk {
    source = "$boot_disk"
  }

  network_interface {
    network = "$network"
    subnetwork = "$subnetwork"

    access_config {
    }
  }

$opt_str
}
EOL
    }

    sub make_scope_string
    {
        my $self = shift(@_);
        my ($scopes) = @_;
        my @ts = split(",", $scopes);
        if (@ts <= 0) {
            return;
        }
        my $str = join("\n", map {qq|      "$_",|} @ts);
        return <<EOL
  service_account {
    scopes = [
$str
    ]
  }
EOL
    }

    sub make_tag_string
    {
        my $self = shift(@_);
        my ($tags) = @_;
        my @ts = split(",", $tags);
        if (@ts <= 0) {
            return;
        }
        my $str = join("\n", map {qq|    "$_",|} @ts);
        return <<EOL
  tags = [
$str
  ]
EOL
    }
}
1;
