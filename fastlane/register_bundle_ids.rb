#!/usr/bin/env ruby
# Registers bundle IDs + App Store Connect app records for the multi-country
# iOS flavors, using API-key auth (no Apple ID password / 2FA needed).
#
# Idempotent: skips anything that already exists.
#
# Requires env:
#   CONNECT_KEY_ID, CONNECT_ISSUER_ID, CONNECT_KEY_PATH
# Optional:
#   CONNECT_TEAM_NAME (defaults to "Adelaidensis Pty Ltd")

require 'fastlane'
require 'spaceship'

%w[CONNECT_KEY_ID CONNECT_ISSUER_ID CONNECT_KEY_PATH].each do |v|
  abort "missing env: #{v}" unless ENV[v] && !ENV[v].empty?
end

key_path = File.expand_path(ENV['CONNECT_KEY_PATH'])
abort ".p8 not found at #{key_path} — run fastlane/setup-doppler.sh" unless File.exist?(key_path)

token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV['CONNECT_KEY_ID'],
  issuer_id: ENV['CONNECT_ISSUER_ID'],
  filepath: key_path
)
Spaceship::ConnectAPI.token = token

FLAVORS = [
  { bundle_id: 'eu.europa.ec.euidi.au', name: 'EUDI Wallet AU', sku: 'eu-europa-ec-euidi-au' },
  { bundle_id: 'eu.europa.ec.euidi.in', name: 'EUDI Wallet IN', sku: 'eu-europa-ec-euidi-in' }
]

FLAVORS.each do |f|
  # 1. Bundle ID (Developer Portal)
  existing_bundle = Spaceship::ConnectAPI::BundleId.find(f[:bundle_id])
  if existing_bundle
    puts "[=] bundle id already registered: #{f[:bundle_id]}"
  else
    bundle = Spaceship::ConnectAPI::BundleId.create(
      name: f[:name],
      platform: 'IOS',
      identifier: f[:bundle_id],
      seed_id: ENV['CONNECT_TEAM_ID']
    )
    puts "[+] created bundle id: #{bundle.identifier}"
  end

  # 2. App Store Connect app record (requires Admin-role API key)
  existing_app = Spaceship::ConnectAPI::App.find(f[:bundle_id])
  if existing_app
    puts "[=] ASC app already exists: #{f[:bundle_id]} (id=#{existing_app.id})"
  else
    begin
      app = Spaceship::ConnectAPI::App.create(
        name: f[:name],
        version_string: '1.0',
        sku: f[:sku],
        primary_locale: 'en-US',
        bundle_id: f[:bundle_id],
        platforms: ['IOS']
      )
      puts "[+] created ASC app: #{app.name} (id=#{app.id})"
    rescue Spaceship::AccessForbiddenError => e
      puts "[!] cannot create ASC app for #{f[:bundle_id]} — API key lacks Admin role"
      puts "    create manually at https://appstoreconnect.apple.com/apps"
      puts "    (or rotate the API key to Admin)"
    end
  end
end
puts "done."
