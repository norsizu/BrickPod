import{aa as a,a8 as i}from"./index~ea66e33958.js";import{b as o,m as s}from"./libraryPinsAPI~c9fc5123b8.js";const y={$intentKind:a.Name,async perform(n,t){const{itemId:e}=n;try{const r=await o(e,t);return{pins:await s(r,t),status:i.SUCCESS}}catch(r){throw new Error(`an error occurred at AddLibraryPinIntentController: ${r}`)}}};export{y as DeleteLibraryPinIntentController};

