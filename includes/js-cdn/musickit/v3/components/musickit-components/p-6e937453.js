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
import{B as i}from"./p-70a2b3a8.js";var t,a,s,o,n,e,c,m,d;!function(i){i.episode="episode",i.podcast="podcast",i.videoEmbed="videoEmbed"}(t||(t={})),function(i){i.ratings="ratings",i.pse="pse",i.productPlacement="productPlacement"}(a||(a={})),function(i){i.album="album",i.artist="artist",i.episode="episode",i.movie="movie",i.musicVideo="musicVideo",i.playlist="playlist",i.podcast="podcast",i.post="post",i.show="show",i.song="song",i.radioStation="radioStation",i.uploadedVideo="uploadedVideo"}(s||(s={})),function(i){i.description="description"}(o||(o={})),function(i){i.none="none",i.small="small",i.medium="medium",i.large="large",i.minimum="minimum",i.full="full"}(n||(n={})),function(i){i.light="light",i.dark="dark",i.auto="auto"}(e||(e={})),function(i){i.music="music",i.tv="tv",i.podcasts="podcasts"}(c||(c={})),function(i){i.bonus="bonus",i.full="full",i.trailer="trailer"}(m||(m={})),function(i){i.current="current",i.episodic="episodic",i.serial="serial"}(d||(d={}));const l={[t.podcast]:[{minWidth:0,maxWidth:425,label:n.small},{minWidth:425,maxWidth:480,label:n.medium},{minWidth:480,label:n.large}],[t.videoEmbed]:[{minWidth:0,maxWidth:578,label:n.minimum},{minWidth:578,label:n.full}]};l[t.episode]=l[t.podcast];const u={breakpoints:l,musicKitSrc:"https://js-cdn.music.apple.com/musickit/v2/musickit.js",mediaKitSrc:"https://js-cdn.music.apple.com/musickit/v2/amp/mediakit.js",isDevBuild:i&&i.isDev,dataAttribute:"data-apple-musickit",fontBaseHref:"//www.apple.com/wss/fonts",fontFamilies:["SF+Pro,v4"],notificationMS:3e3,interactionTimeoutMS:4e3};export{e as C,s as M,a as O,t as P,n as b,u as c,c as r}