import {z} from '@parklink/contracts';
export const ACTION={SEARCH:'search',RESERVE:'reserve',LIST:'list_reservations',CANCEL:'cancel',PAY:'pay',CLARIFY:'clarify'} as const;
export const IntentSchema=z.object({
 action:z.enum([ACTION.SEARCH,ACTION.RESERVE,ACTION.LIST,ACTION.CANCEL,ACTION.PAY,ACTION.CLARIFY]),
 sort:z.enum(['nearest','cheapest']),text:z.string().max(100),
 start:z.string().datetime({offset:true}).nullable(),end:z.string().datetime({offset:true}).nullable(),
 reservationId:z.uuid().nullable(),maxRate:z.number().int().positive().max(1000000).nullable(),
 reply:z.string().min(1).max(800)
}).strict();
export type Intent=z.infer<typeof IntentSchema>;
export const ChatInputSchema=z.object({
 requestId:z.uuid(),conversationId:z.uuid().optional(),message:z.string().min(1).max(1500),
 latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),
 radius:z.number().int().min(100).max(50000).default(5000),
 start:z.string().datetime({offset:true}).optional(),end:z.string().datetime({offset:true}).optional()
}).strict().refine(p=>(!p.start&&!p.end)||(!!p.start&&!!p.end&&Date.parse(p.start)<Date.parse(p.end)),{message:'Choose a valid complete interval'});
export type ChatInput=z.infer<typeof ChatInputSchema>;
export interface IntentContext{now:string;start?:string;end?:string;history:Array<{user:string;assistant:string}>}
export interface IntentProvider{readonly name:string;interpret(text:string,context:IntentContext):Promise<Intent>}
