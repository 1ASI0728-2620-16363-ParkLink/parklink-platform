export interface PaymentOrder { id:string; amount:number; currency:string; scenario:string }
export interface PaymentOutcome { state:string; reference?:string; checkoutUrl?:string; amount?:number; currency?:string }
export interface PaymentGateway {
 readonly name:string;
 prepare(order:PaymentOrder):Promise<PaymentOutcome>;
 reconcile(order:PaymentOrder):Promise<PaymentOutcome>;
 refund(reference:string,amount:number,key:string):Promise<string>;
}
