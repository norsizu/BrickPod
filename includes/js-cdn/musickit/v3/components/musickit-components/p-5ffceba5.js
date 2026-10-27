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
import{u as o}from"./p-2dad192d.js";const i=async(i,d)=>{var l,v,n,u,a,r,s;if(!o.isLibraryType(d))return d;const t=await i.music(`/v1/me/library/songs/${d}`,{include:"catalog"});return null===(s=null===(r=null===(a=null===(u=null===(n=null===(v=null===(l=null==t?void 0:t.data)||void 0===l?void 0:l.data)||void 0===v?void 0:v[0])||void 0===n?void 0:n.relationships)||void 0===u?void 0:u.catalog)||void 0===a?void 0:a.data)||void 0===r?void 0:r[0])||void 0===s?void 0:s.id};export{i as f}