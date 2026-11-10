import {copyFile,mkdir,writeFile} from 'node:fs/promises';
const assets=new URL('../apps/mobile/assets/',import.meta.url);
await mkdir(new URL('fonts/',assets),{recursive:true});
for(const [source,target] of [
 ['https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf','fonts/Inter.ttf'],
 ['https://raw.githubusercontent.com/google/fonts/main/ofl/inter/OFL.txt','fonts/OFL.txt']
]){
 const response=await fetch(source);if(!response.ok)throw new Error(`Unable to download licensed font: ${response.status}`);
 await writeFile(new URL(target,assets),Buffer.from(await response.arrayBuffer()));
}
await copyFile(new URL('../reference/ParkLink-Report/assets/chapter-6/figma/brand-logo-full.png',import.meta.url),new URL('images/parklink_logo.png',assets));
console.log('Synced original ParkLink logo and licensed Inter font. Run only when refreshing assets; bundled files work offline.');
