# Self service fact aims to have all chunks reporting as true, this indicates ideal state, any individual chunk reporting false should be alerted on and checked against documentation for next steps
require 'puppet'
# Use shared logic from PuppetSelfService
require_relative '../shared/puppet_self_service'
### TODO now puppet is required, use puppet functions insead of execute shell blocks where possible

Facter.add(:self_service, type: :aggregate) do
  confine kernel: 'Linux'
  confine { Facter.value(:pe_build) }

  puppet_bin = '/opt/puppetlabs/bin/puppet'

  chunk(:S0001) do
    # Is the Agent Service Running and Enabled
    { S0001: PuppetSelfService.service_running_enabled('puppet') }
  end

  chunk(:S0002) do
    # Is the Pxp-Agent Service Running and Enabled
    { S0002: PuppetSelfService.service_running_enabled('pxp-agent') }
  end

  chunk(:S0003) do
    # check for noop logic flip as false is the desired state
    { S0003: !Puppet.settings['noop'] }
  end

  chunk(:S0004) do
    next unless PuppetSelfService.primary?
    # Is PE and has clienttools covers pe-psql and compilers
    # Check for service status that is not green, potentially need a better way of doing this, or perhaps calling the api directly for each service
    result = Facter::Core::Execution.execute("#{puppet_bin} infrastructure status")
    if result.include?('Unknown') || result.include?('Unreachable')
      { S0004: false }
    else
      { S0004: true }
    end
  end

  chunk(:S0005) do
    next unless File.exist?('/etc/puppetlabs/puppet/ssl/ca/ca_crt.pem') || File.exist?('/etc/puppetlabs/puppetserver/ca/ca_crt.pem')
    raw_ca_cert = if File.exist? '/etc/puppetlabs/puppetserver/ca/ca_crt.pem'
                    File.read '/etc/puppetlabs/puppetserver/ca/ca_crt.pem'
                  else
                    File.read '/etc/puppetlabs/puppet/ssl/ca/ca_crt.pem'
                  end
    certificate = OpenSSL::X509::Certificate.new raw_ca_cert
    result = certificate.not_after - Time.now
    { S0005: result > 7_776_000 }
  end

  chunk(:S0006) do
    # check for sustained load average greater than available cores
    { S0006: Facter.value(:load_averages)['15m'] <= Facter.value(:processors)['count'] }
  end
  chunk(:S0007) do
    next unless PuppetSelfService.primary? || PuppetSelfService.replica? || PuppetSelfService.postgres?
    # check postgres data mount has at least 20% free
    percent = Facter.value(:pe_postgresql_info)['data_partition_available_bytes'].fdiv(Facter.value(:pe_postgresql_info)['data_partition_size_bytes']) * 100
    { S0007: percent >= 20 }
  end
  chunk(:S0008) do
    next unless PuppetSelfService.primary? || PuppetSelfService.replica? || PuppetSelfService.compiler? || PuppetSelfService.legacy_compiler?
    # check codedir data mount has at least 20% free
    { S0008: `df -m #{Puppet.settings['codedir']}`.split(%r{\b})[26].to_i <= 80 }
  end

  chunk(:S0009) do
    next unless  PuppetSelfService.replica? || PuppetSelfService.compiler? || PuppetSelfService.legacy_compiler? || PuppetSelfService.primary?
    # Is the Pe-puppetsever Service Running and Enabled
    { S0009: PuppetSelfService.service_running_enabled('pe-puppetserver') }
  end

  chunk(:S0010) do
    next unless PuppetSelfService.replica? || PuppetSelfService.compiler? || PuppetSelfService.primary?
    # Is the pe-puppetdb Service Running and Enabled
    { S0010: PuppetSelfService.service_running_enabled('pe-puppetdb') }
  end

  chunk(:S0011) do
    next unless PuppetSelfService.replica? || PuppetSelfService.postgres? || PuppetSelfService.primary?
    # Is the pe-postgres Service Running and Enabled
    postgresversion = PuppetSelfService.pe_postgres_service_name
    { S0011: PuppetSelfService.service_running_enabled(postgresversion.to_s) }
  end
end
