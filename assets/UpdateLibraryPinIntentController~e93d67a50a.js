import{ac as e,a8 as i}from"./index~ea66e33958.js";import{d as o,m as s}from"./libraryPinsAPI~c9fc5123b8.js";const d={$intentKind:e.Name,async perform(t,n){const{itemId:a}=t;try{const r=await o(a,t.action,n);return{pins:await s(r,n),status:i.SUCCESS}}catch(r){throw new Error(`an error occurred at UpdateLibraryPinIntentController: ${r}`)}}};export{d as UpdateLibraryPinIntentController};

