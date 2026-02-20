# Boosted Doctor (Boosted VESC Bridge)

This is a package for using Boosted Board (and Rev Scooter) batteries with VESC controllers or VESC Express modules. The package implements the commands and command parsing for Boosted's CAN communications and implements the battery ping needed for the battery to stay on for more than 10 minutes. 

In VESC tool, users are able to check individual cell voltages of their XR and Rev batteries. In the event of Red Light of Death (RLOD), users are also able to clear RLOD within VESC Tool.

Robert Scullin - Boosted CANBUS Research: https://beambreak.org / https://github.com/rscullin/beambreak
Alex Krysl - Boosted CANBUS Research: https://github.com/axkrysl47/BoostedBreak 
Simon Wilson - VESC Express Implementation: https://github.com/techfoundrynz
David Wang - Boosted CANBUS Research: https://www.xrgeneralhospital.com/