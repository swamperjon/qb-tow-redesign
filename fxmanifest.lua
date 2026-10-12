fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Kakarot'
description 'Progression-based towing and roadside assistance for QBCore'
version '2.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua',
    'shared/contracts.lua',
    'locales/en.lua',
    'locales/*.lua'
}

client_scripts {
    'client/main.lua'
}

server_script 'server/main.lua'
