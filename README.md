# wlanpi-bluetooth
Enables Bluetooth management access to the WLAN Pi

<h1>Dependencies</h1>
<p>Requires bluez-tools.</p>
Install via <code>sudo apt-get install [debfile]</code> to manage dependencies

<h1>Post Installation</h1>
<p>The DHCP server should be restarted through reboot or <code>sudo systemctl restart isc-dhcp-server</code></p>

<h1>Long Running Services</h1>
<p>The following services are installed and autostarted by the system</p>
<ul>
  <li>
    <strong>bt-agent</strong> 
    The authenticator service. Automatically started by the system for No Input No Output authentication. Bluetooth discoverability and pairability are default off.
  </li>
  <li>
  <strong>bt-network</strong> 
    The bluetooth network service. Automatically started by the system. Registeres a Network Aggregation Point server
  </li>  
</ul>
  
<h1>Runtime Services</h1>
<p>The following services are installed and used manually to manage the Bluetooth connection</p>
<ul>
  <li>
    <strong>bt-timedpair</strong> 
    30s pairing window. This service is one shot and enables discoverability and pairability for 30s
  </li>
</ul>


<h1>Usage</h1>
<p>To pair a device, run <code>sudo systemctl start bt-timedpair</code></p>
<p>After 30s the Bluetooth service will no longer be visible and clients which have already scanned it will not be able to pair</p>

