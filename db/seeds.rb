Rails.logger.info '🌱 Starting database seeding...'

Rails.root.glob('db/seeds/*.rb').sort.each do |file|
  Rails.logger.info "➡️  Loading #{File.basename(file)}..."
  load file
end

Rails.logger.info '✅ Seeding complete!'
