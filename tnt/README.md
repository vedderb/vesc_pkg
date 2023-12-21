<H1> Trick and Trail VESC Package </H1>
<P>by Mike Silberstein (send questions, comments, requests to izzyvesc@gmail.com) </P>

<P>Trick and Trail Package was developed based on Float Package 1.2 by Surfdado and Niko for self-balanced boards. It departs from the traditional PID control scheme that is rooted in the balance robot design. This is replaced with a user defined, current output curve that is based on board pitch. This allows for an infinite number of throttle/braking curves that gives the user the ability to truly tune the board how they want.</P>

<P><a href="https://github.com/Izzygit/TrickandTrailReleases/wiki">READ THE WIKI</a> https://github.com/Izzygit/TrickandTrailReleases/wiki </P>

<H3>Features</H3>
<UL>
 <li>Current output defined by a series of points, input by the user</li>
 <li>Alternative proportional gain user inputs</li>
 <li>Optional independent brake curve</li>
 <li>Roll kp curves for acceleration and braking</li>
 <li>Roll kp modification for low speeds</li>
 <li>Surge</li>
 <li>Traction control</li>
 <li>Sticky tilt</li>
 <li>Dynamic Stability</li>
</UL>

<h3>Default Settings</h3>
<P>Default settings are based on 15s Hypercore (Future Motion motor) board set up. The default settings are what I ride for trails. The exceptions are surge and traction control which are disabled by default. These are more advanced behaviors that should be tuned by the user. For more instructions on setting up your board please refer to the <a href="https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide">Set Up Guide.</a> https://github.com/Izzygit/TrickandTrailReleases/wiki/Set-Up-Guide</P>

<H2>Change Log</H2> 
<H3>1.1 </H3>
<UL>
 <LI><B>Version 1.1 parameters are not compatible with v1.0 and will be set to default. Screenshot your tunes to save.</B></LI>
 <LI><I>Features</I>
    <UL>
      <LI>Dynamic Stability
        <UL>
          <LI>Increase pitch current and pitch rate response (kp rate) at higher speeds or with remote control.</LI>
          <LI>Found in the tune modifiers menu.</LI>
          <LI>Speed stability enabled by default</LI>
          <LI>Enabling remote control stability disables remote tilt.</LI>
          <LI>New indicators on AppUI for relative stability (0-100%) and the added kp and kp rate from stability applied to the pitch response.</LI>
        </UL>
      </LI>
      <LI>Independent braking curve
        <UL>
          <LI>New menu "Brake".</LI>
          <LI>Disabled by default.</LI>
          <LI>Uses the same layout and logic as the acceleration menu.</LI>
       </UL>
        </LI>
    </UL>
    </LI>
<LI><I>Fixes/Improvements</I>
   <UL>
      <LI>Changed name of "Pitch" menu to "Acceleration".</LI>
      <LI>Changed name of "Surge / Traction Control" menu to "Tune Modifiers"</LI>
      <LI>Removed limitations on pitch current and kp that only allowed increasing values. Now decreasing or negative values are allowed. Pitch must still be increasing.</LI>
      <LI>Added a significant digit to the first two pitch values on the acceleration and brake curves for more precision.</LI>
      <LI>Reorganized the AppUI screen.</LI>
      <LI>Cleaned up AppUI to remove unused quicksave buttons.</LI>
      <LI>Updated traction control to remove false start scenario.</LI>
    </UL> 
  </LI>
</UL>
<H3>1.0 </H3>
<UL>
 <LI>Initial release.</LI>
</UL>
