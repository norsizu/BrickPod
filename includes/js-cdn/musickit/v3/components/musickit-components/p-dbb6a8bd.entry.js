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
import{r as i,a as t,h as n,c as s,H as o}from"./p-70a2b3a8.js";import{s as a}from"./p-b465e2cb.js";const e=new Map,r=class{constructor(t){i(this,t),this.iconContent=void 0,this.name=void 0}async nameChanged(i,t){i!==t&&await this.loadAsset()}async componentWillLoad(){await this.loadAsset()}async loadAsset(){var i,n;const{name:s}=this;if(!(i=>(null==i?void 0:i.length)>0&&/^[a-zA-Z0-9-.]+$/.test(i))(s))return this.iconContent="",void console.warn(`"${s}" is not a valid icon name.`);if(e.has(s))this.iconContent=e.get(s);else try{const o=await fetch(t(`assets/icons/${s}.svg`));if(!o.ok)throw this.iconContent="",new Error("Icon not found");this.iconContent=null!==(n=null===(i=a(await o.text()))||void 0===i?void 0:i.outerHTML)&&void 0!==n?n:"",e.set(s,this.iconContent)}catch(o){console.warn("Cannot load icon",this.name),this.iconContent=""}}render(){return n(o,{class:"icon",role:"presentation","aria-hidden":"true",innerHTML:this.iconContent})}get el(){return s(this)}static get watchers(){return{name:["nameChanged"]}}};r.style=".icon{display:block}.icon svg{width:inherit;height:inherit;display:block;color:currentColor;pointer-events:none}.icon svg *{fill:currentColor}";export{r as amp_icon}