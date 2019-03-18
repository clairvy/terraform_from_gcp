#!/usr/bin/env perl

use strict;
use warnings;

{
    package TerraformFromGCP;
    
    my @PACKAGES = qw(
        GoogleComputeNetwork
        GoogleComputeSubnetwork
        GoogleComputeFirewall
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
        if (exists $ENV{GCLOUD_CMD}) {
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
    sub list_cmd { "$TerraformFromGCP::GCLOUD_CMD compute networks list" };
    sub resource_name { 'google_compute_network' };
}

{
    package GoogleComputeSubnetwork;
    use base qw/TerraformResource/;
    sub list_cmd { "$TerraformFromGCP::GCLOUD_CMD compute networks subnets list" };
    sub resource_name { 'google_compute_subnetwork' };

    sub template_for_oneline
    {
        my $self = shift(@_);
        my ($param) = @_;
        my ($name, $cidr) = @{$param}[0, 3];
        my $resource_name = $self->resource_name();
        return <<EOL;
# terraform import $resource_name.$name $name
resource "$resource_name" "$name" {
  name = "$name"
  ip_cidr_range = "$cidr"
}
EOL
    }
}

{
    package GoogleComputeFirewall;
    use base qw/TerraformResource/;
    sub list_cmd { "$TerraformFromGCP::GCLOUD_CMD compute firewall-rules list" };
    sub resource_name { 'google_compute_firewall' };

    sub template_for_oneline
    {
        my $self = shift(@_);
        my ($param) = @_;
        #NAME                    NETWORK  SRC_RANGES       RULES                         SRC_TAGS  TARGET_TAGS
        #allow-from-ug           default  202.221.220.251  tcp:22                                  server-ug
        #default-allow-icmp      default  0.0.0.0/0        icmp
        #default-allow-internal  default  10.128.0.0/9     tcp:0-65535,udp:0-65535,icmp
        #default-allow-rdp       default  0.0.0.0/0        tcp:3389
        #default-allow-ssh       default  0.0.0.0/0        tcp:22
        my ($name, $network, $src, $rule_expr, $tags) = @{$param}[0, 1, 2, 3, 4];
        my $resource_name = $self->resource_name();
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

1;
