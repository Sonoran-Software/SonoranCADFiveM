fx_version 'cerulean'
games {'gta5'}

author 'Sonoran CAD'
description 'Sonoran CAD FiveM Integration'
version '4.0.21'

server_scripts {
    'lua/sonoran/init.lua'
    ,'core/http.js'
    ,'core/apiws.js'
    ,'core/unzipper/unzip.js'
    ,'core/image.js'
    ,'core/pdf.js'
    ,'core/logging.lua'
    ,'core/shared_functions.lua'
    ,'core/configuration.lua'
    ,'core/sonoran_api.lua'
    ,'core/linking_sv.lua'
    ,'core/server.lua'
    ,'core/commands.lua'
    ,'core/httpd.lua'
    ,'core/unittracking.lua'
    ,'core/updater.lua'
    ,'core/apicheck.lua'
    ,'configuration/*_config.lua'
    ,'core/plugin_loader.lua'
    ,'submodules/**/sv_*.lua'
    ,'submodules/**/sv_*.js'
    ,'core/screenshot.lua'
}
client_scripts {
    'core/logging.lua'
    ,'core/headshots.lua'
    ,'core/shared_functions.lua'
    ,'core/client.lua'
    ,'core/linking_cl.lua'
    ,'core/lighting.lua'
    ,'configuration/*_config.lua'
    ,'submodules/**/cl_*.lua'
    ,'submodules/**/cl_*.js'
}

ui_page 'core/client_nui/index.html'

files {
    'stream/**/*.ytyp',
    'core/client_nui/*.html',
    'core/client_nui/js/*.js',
    'core/client_nui/sounds/*.mp3',
    'core/client_nui/img/*.*',
    'submodules/**/*.mp3',
    'submodules/caddisplay/html/**/*',
    'submodules/postals/*.json',
    'submodules/recordPrinter/html/main.js',
    'submodules/recordPrinter/html/style.css',
    'submodules/recordPrinter/html/ui.html',
    'submodules/recordPrinter/pdfs/**/*.pdf',
}

data_file 'DLC_ITYP_REQUEST' 'stream/**/*.ytyp'
