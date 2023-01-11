require "./class/app/nzsyncer.cr"

NBXTool::Log.configure(:info)

nzs = NZSyncer.new("./conf/nbx.yaml", :prod)

nzs.sync_zabbix_with_netbox
