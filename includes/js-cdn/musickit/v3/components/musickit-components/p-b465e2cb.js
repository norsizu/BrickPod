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
const e=new Set(["svg","g","path","defs","filter","feoffset","fegaussianblur","fecolormatrix","use","symbol","title","desc","style","rect","circle","ellipse","line","polygon","polyline","mask"]),t=new Set(["id","class","xmlns","xmlns:xlink","viewbox","width","height","version","xml:space","role","focusable","aria-hidden","aria-role","data-testid","d","points","x","y","x1","y1","x2","y2","cx","cy","r","rx","ry","fill","fill-rule","fill-opacity","stroke","stroke-width","stroke-miterlimit","stroke-linejoin","stroke-linecap","stroke-dasharray","clip-rule","opacity","overflow","style","transform","filterunits","dy","in","result","stddeviation","values","xlink:href","href","filter"]),l=/^on/i,r=/^\s*javascript:/i,i=i=>{const s=(new DOMParser).parseFromString(i,"text/html").querySelector("svg");return s?([s,...Array.from(s.querySelectorAll("*"))].forEach((i=>{e.has(i.tagName.toLowerCase())?Array.from(i.attributes).forEach((e=>{const s=e.name.toLowerCase();(!t.has(s)||l.test(e.name)||r.test(e.value))&&i.removeAttribute(e.name)})):i.remove()})),s):null};export{i as s}