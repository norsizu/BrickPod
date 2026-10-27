/*!
 * IMPORTANT NOTE:
 * 
 *   This file is licensed only for the use of Apple developers in providing MusicKit Web Services,
 *   and is subject to the Apple Media Services Terms and Conditions and the Apple Developer Program
 *   License Agreement. You may not copy, modify, re-host, or create derivative works of this file or the
 *   accompanying Documentation, or any part thereof, including any updates, without Apple's written consent.
 * 
 *   ACKNOWLEDGEMENTS:
 *   https://js-cdn.music.apple.com/musickit/v1/acknowledgements.txt
 */
function n(n,t,o){return t?n.map((n=>{const[r,s]=n,c=s.bind(o);return t.addEventListener(r,c),[r,c]})):[]}function t(n,t){n&&t&&n.forEach((n=>{const[o,r]=n;t.removeEventListener(o,r)}))}export{n as s,t}