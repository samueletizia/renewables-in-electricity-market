
using Gurobi,JuMP
using Plots, Random, Printf, XLSX, CSV, DataFrames, Distributions, MathOptInterface

# SETS and DATA

GEN_S=["S1","S2","S3","S4"]                  # price MAKER generators
GEN_O=["O1","O2","O3","O4"]                  # price TAKER generators
DEMAND=["D1","D2","D3","D4"]                 # demand
NODE=["N1","N2","N3","N4","N5","N6"]         # nodes

S=length(GEN_S)
O=length(GEN_O)
D=length(DEMAND)
N=length(NODE)
# X=length(SCENARIOS_TOT)

########################### SCENARIOS BUILDING ################################

SCENARIOS_TOT = String[]
for i in 1:1000
    push!(SCENARIOS_TOT, "S" * string(i))
end

X=length(SCENARIOS_TOT)     # ALL THE SCENARIOS


WIND_SCENARIO=["WQ1","WQ2","WQ3","WQ4","WQ5","WQ6","WQ7","WQ8"]   
NON_STRATEGIC_PRICE=["OP1","OP2","OP3","OP4","OP5"]
DEMAND_PRICE=["DP1","DP2","DP3","DP4","DP5"]
DEMAND_QUANTITY=["DQ1","DQ2","DQ3","DQ4","DQ5"]

w_q=[0 0.2 0.4 0.6 0.8 1 1.2 1.33]         # wind quantity
d_q=[0.2 0.5 0.9 1 1.08]                   # demand quantity
d_p=[0.7 0.8 1 1.2 1.3]                    # nonstrategic production cost
o_p=[0.7 0.8 1 1.2 1.3]                    # demand bid price


WQ=length(w_q)       # wind quantity
DQ=length(d_q)       # demand quantity
OP=length(o_p)       # nonstrategic production cost
DP=length(d_p)       # demand bid price

scenarioz_coefficient=zeros(4,X)       # matrix where each row represent a source of uncertainty

global iiind=1

for wq = 1:WQ
    for dq = 1:DQ
        for op = 1:OP
            for dp = 1:DP
            scenarioz_coefficient[:,iiind] = [w_q[wq]; d_q[dq]; o_p[op]; d_p[dp]] 
            global iiind += 1 
            end
        end
    end
end

Y=100                            # in_sample scenarios
W=X-Y                            # out_sample scenarios

sY=zeros(Y)
scenarios_Y_coeff=zeros(4,Y)


Random.seed!(1234)
sY = sort(randperm(X)[1:Y])

global hh=1

for y=1:Y
    o=sY[y]
    scenarios_Y_coeff[:,hh]=scenarioz_coefficient[:,o]
global hh=hh+1
end

prob=1/Y

wind_x=1     # referring to the scenario, these are index names which refer to what coefficient I will be using 
dem_x=2
ooo_p=3
dem_p=4


# PREVIOUS DATA


D_Location=[3 4 5 6]    # demand location
S_Location=[1 2 3 6]    # price MAKER generators locations
O_Location=[1 2 3 5]    # price TAKER generators locations

D_quantity=[200 400 300 250]       # MW             ############################  coefficient multiplication 
D_quantity_Y=zeros(D,Y)
for d=1:D
    for y=1:Y
        D_quantity_Y[d,y]= D_quantity[d]*scenarios_Y_coeff[dem_x,y]
    end
end


D_bid_price=[26.5 24.7 23.1 22.5]    # euro/MWh     ############################  coefficient multiplication
D_bid_price_Y=zeros(D,Y)
for d=1:D
    for y=1:Y
        D_bid_price_Y[d,y]= D_bid_price[d]*scenarios_Y_coeff[dem_p,y]
    end
end




S_capacity=[155 100 155 197]     # MW
S_cost=[15.2 23.4 15.2 19.1]     # euro/MWh



O_capacity=[0.75*450 350 210 80]      # MW        #############################   coefficient multiplication
O_capacity_Y=zeros(O,Y)
for o=1:O
    for y=1:Y
    if o==1
        O_capacity_Y[o,y]= O_capacity[o]*scenarios_Y_coeff[wind_x,y]
    else
        O_capacity_Y[o,y]= O_capacity[o]
    end
end
end


O_cost=[0 5 20.1 24.7]           # euro/MWh        ############################   coefficient multiplication
O_cost_Y=zeros(O,Y)
for o=1:O
    for y=1:Y
        O_cost_Y[o,y]= O_cost[o]*scenarios_Y_coeff[ooo_p,y]
    end
end

S_ramp=[90 85 90 120]    # MW/h
O_ramp=[0 350 170 80]    # MW/h

susceptance=50
BB=1/susceptance

Big_M = 10^4


# OPTIMIZATION MODEL - VARIABLE

TWO_FOUR= Model(Gurobi.Optimizer)

@variable(TWO_FOUR, S_prod[1:S,1:Y])            # production of strategic offer for each scenario
@variable(TWO_FOUR, O_prod[1:O,1:Y])            # production of non-strategic offer for each scenario

@variable(TWO_FOUR, lambda[1:Y])                # markt price for each scenario

@variable(TWO_FOUR, S_alpha_offer[1:S])         # offer price for each strategic producer
@variable(TWO_FOUR, demand[1:D,1:Y])            # demand covered

@variable(TWO_FOUR, mu_D_up[1:D,1:Y])
@variable(TWO_FOUR, mu_D_down[1:D,1:Y])

@variable(TWO_FOUR, mu_O_up[1:O,1:Y])
@variable(TWO_FOUR, mu_O_down[1:O,1:Y])

@variable(TWO_FOUR, mu_S_up[1:S,1:Y])
@variable(TWO_FOUR, mu_S_down[1:S,1:Y])

@variable(TWO_FOUR, epsi_D_up[1:D,1:Y],Bin)                                                     # 11
@variable(TWO_FOUR, epsi_D_down[1:D,1:Y],Bin)                                                   # 16

@variable(TWO_FOUR, epsi_O_up[1:O,1:Y],Bin)                                                     # 21
@variable(TWO_FOUR, epsi_O_down[1:O,1:Y],Bin)                                                   # 26

@variable(TWO_FOUR, epsi_S_up[1:S,1:Y], Bin)                                                    # 31
@variable(TWO_FOUR, epsi_S_down[1:S,1:Y], Bin)                                                  # 36


# GENERAL CONSTRAINTS

#@constraint(TWO_FOUR,[s=1:S], S_alpha_offer[s] >= S_cost[s])                                                # 1
@constraint(TWO_FOUR,[s=1:S], S_alpha_offer[s]>=0)                                                           # 2
@constraint(TWO_FOUR,[d=1:D,y=1:Y], - D_bid_price_Y[d,y] + mu_D_up[d,y] - mu_D_down[d,y] + lambda[y] == 0)   # 3
@constraint(TWO_FOUR,[s=1:S,y=1:Y], S_alpha_offer[s] + mu_S_up[s,y] - mu_S_down[s,y] - lambda[y] == 0)       # 4
@constraint(TWO_FOUR,[o=1:O,y=1:Y], O_cost_Y[o,y] + mu_O_up[o,y] - mu_O_down[o,y] - lambda[y] == 0)          # 5
@constraint(TWO_FOUR,[y=1:Y], sum(demand[d,y] for d=1:D) - sum(S_prod[s,y] for s=1:S) - sum(O_prod[o,y] for o=1:O) == 0) # 6 power balance  ###########

# DEMAND

@constraint(TWO_FOUR, [d=1:D,y=1:Y], demand[d,y]<=D_quantity_Y[d,y])                                   # 7
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_up[d,y]>=0)                                                   # 8
@constraint(TWO_FOUR, [d=1:D,y=1:Y], D_quantity_Y[d,y] - demand[d,y] <= epsi_D_up[d,y]*Big_M)          # 9
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_up[d,y] <= (1 - epsi_D_up[d,y])*Big_M)                        # 10
# 11 is in the variable
@constraint(TWO_FOUR,[d=1:D,y=1:Y], demand[d,y] >= 0)                                                  # 12
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_down[d,y] >= 0)                                               # 13
@constraint(TWO_FOUR,[d=1:D,y=1:Y], demand[d,y] <= epsi_D_down[d,y]*Big_M)                             # 14
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_down[d,y] <= (1 - epsi_D_down[d,y])*Big_M)                    # 15
# 16 is in the variable

# PRICE MAKER - LEADER - S

@constraint(TWO_FOUR, [s=1:S,y=1:Y], S_prod[s,y]<=S_capacity[s])                                       # 17
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_up[s,y]>=0)                                                   # 18
@constraint(TWO_FOUR, [s=1:S,y=1:Y], S_capacity[s] - S_prod[s,y] <= epsi_S_up[s,y]*Big_M)              # 19
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_up[s,y] <= (1 - epsi_S_up[s,y])*Big_M)                        # 20
# 21 is in the variable
@constraint(TWO_FOUR,[s=1:S,y=1:Y], S_prod[s,y] >= 0)                                                  # 22
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_down[s,y] >= 0)                                               # 23
@constraint(TWO_FOUR,[s=1:S,y=1:Y], S_prod[s,y] <= epsi_S_down[s,y]*Big_M)                             # 24
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_down[s,y] <= (1 - epsi_S_down[s,y])*Big_M)                    # 25
# 26 is in the variable

# PRICE TAKER - FOLLOWERS - O

@constraint(TWO_FOUR, [o=1:O,y=1:Y], O_prod[o,y]<=O_capacity_Y[o,y])                                     # 27
@constraint(TWO_FOUR,[o=1:O,y=1:Y], mu_O_up[o,y]>=0)                                                     # 28
@constraint(TWO_FOUR, [o=1:O,y=1:Y], O_capacity_Y[o,y] - O_prod[o,y] <= epsi_O_up[o,y]*Big_M)            # 29
@constraint(TWO_FOUR,[o=1:O,y=1:Y], mu_O_up[o,y] <= (1 - epsi_O_up[o,y])*Big_M)                          # 30
                                                                                                         # 31 is in the variable
@constraint(TWO_FOUR,[o=1:O,y=1:Y], O_prod[o,y] >= 0)                                                    # 32
@constraint(TWO_FOUR,[o=1:O,y=1:Y], mu_O_down[o,y] >= 0)                                                 # 33
@constraint(TWO_FOUR,[o=1:O,y=1:Y], O_prod[o,y] <= epsi_O_down[o,y]*Big_M)                               # 34
@constraint(TWO_FOUR,[o=1:S,y=1:Y], mu_O_down[o,y] <= (1 - epsi_O_down[o,y])*Big_M)                      # 35
                                                                                                         # 36 is in the variable



@objective(TWO_FOUR, Max, sum(prob*(- sum(S_prod[s,y]*S_cost[s] for s=1:S) 
                         + sum(D_bid_price_Y[d,y]*demand[d,y] for d=1:D)
                         - sum(O_cost_Y[o,y]*O_prod[o,y] for o=1:O)
                         - sum(mu_D_up[d,y]*D_quantity_Y[d,y] for d=1:D)
                         - sum(mu_O_up[o,y]*O_capacity_Y[o,y] for o=1:O)) for y=1:Y)
)

start_time = time()
optimize!(TWO_FOUR)
end_time = time()

# PRINTING STRATEGIC OFFER PRICE

for s=1:S
    println("Offer Price ", GEN_S[s], @sprintf(" %.2f \$" , value(S_alpha_offer[s]))," - Production cost: ", @sprintf(" %.2f \$" , S_cost[s]))
end 

# MARKET CLEARING PRICE AT DIFFERENT in-sample SCENARIOS

println("\n")
for y=1:Y
    x=sY[y]
println("Market clearing price at scenario ",SCENARIOS_TOT[x], @sprintf(": %.2f \$" , value(lambda[y])))
end



##################################### ÍN and OUT SAMPLE VISUALIZATION ###################################

# data gaining for the whole scenario (above just the in-sample were calculated)

D_quantity_X=zeros(D,X)
for d=1:D
    for x=1:X
        D_quantity_X[d,x]= D_quantity[d]*scenarioz_coefficient[dem_x,x]
    end
end


D_bid_price=[26.5 24.7 23.1 22.5]    # euro/MWh     ############################
D_bid_price_X=zeros(D,X)
for d=1:D
    for x=1:X
        D_bid_price_X[d,x]= D_bid_price[d]*scenarioz_coefficient[dem_p,x]
    end
end

O_capacity=[0.75*450 350 210 80]      # MW        #############################
O_capacity_X=zeros(O,X)

for o=1:O
    for x=1:X
    if o==1
        O_capacity_X[o,x]= O_capacity[o]*scenarioz_coefficient[wind_x,x]
    else
        O_capacity_X[o,x]= O_capacity[o]
    end
end
end


O_cost=[0 5 20.1 24.7]           # euro/MWh        ############################
O_cost_X=zeros(O,X)
for o=1:O
    for x=1:X
        O_cost_X[o,x]= O_cost[o]*scenarioz_coefficient[ooo_p,x]
    end
end


scenarios_W_coeff=zeros(4,W)
sW = zeros(Int, W)


global www=1

for xx=1:X
    if xx in sY  
    else
        sW[www]=xx
        global www=www+1
end
end


global lll=1

for w=1:W
    w=sW[w]
    scenarios_W_coeff[:,lll]=scenarioz_coefficient[:,w]
global lll=lll+1
end



################################# PROFIT CALCULATION  through a perfect competitive market clearing ####################################

S_cost_out=zeros(S)

for s=1:S
S_cost_out[s]=value(S_alpha_offer[s])
end



TWO_FOUR_OUT= Model(Gurobi.Optimizer)

@variable(TWO_FOUR_OUT, S_prod_out[1:S,1:X])                   # Power generated by MAKER
@variable(TWO_FOUR_OUT, O_prod_out[1:O,1:X]>=0)                # Power generated by TAKER
@variable(TWO_FOUR_OUT, theta_out[1:N,1:X])                    # voltage angle
@variable(TWO_FOUR_OUT, demand_out[1:D,1:X]>=0)                # demand covered

@constraint(TWO_FOUR_OUT, [s=1:S,x=1:X], S_prod_out[s,x]<=S_capacity[s])                    # capacity contraint S
@constraint(TWO_FOUR_OUT, [s=1:S,x=1:X], S_prod_out[s,x]>=0) 
@constraint(TWO_FOUR_OUT, [o=1:O,x=1:X], O_prod_out[o,x]<=O_capacity_X[o,x])                    # capacity contraint O
@constraint(TWO_FOUR_OUT, [x=1:X], theta_out[1,x]==0)                                          # theta of node 1 =0
@constraint(TWO_FOUR_OUT, [d=1:D,x=1:X], demand_out[d,x]<=D_quantity_X[d,x])                    # capacity contraint D


@constraint(TWO_FOUR_OUT, lambda_out[n=1:N,x=1:X],
                                                  - sum(demand_out[d,x]*(D_Location[d]==n ? 1 : 0) for d=1:D)          # if the demand is located in the right node then it is taken into account otherwise not
                                                  + sum(S_prod_out[s,x]*(S_Location[s]==n ? 1 : 0) for s=1:S)                  # same for the production S and O      
                                                  + sum(O_prod_out[o,x]*(O_Location[o]==n ? 1 : 0) for o=1:O)                 
                                                  - sum(BB*(theta_out[n,x]-theta_out[m,x]) for m=1:N) == 0)

@objective(TWO_FOUR_OUT,Max, sum((sum(D_bid_price_X[d,x]*demand_out[d,x] for d=1:D) - sum(S_cost_out[s]*S_prod_out[s,x] for s=1:S) - sum(O_cost_X[o,x]*O_prod_out[o,x] for o=1:O)) for x=1:X)   )

optimize!(TWO_FOUR_OUT)


######################## VISUALIZATION #########################


market_price_out=zeros(N,X)


for x=1:X
for n=1:N
    market_price_out[n,x]=value(dual.(lambda_out[n,x]))
end
end



S_profit_tot=zeros(S,X)
O_profit_tot=zeros(O,X)
D_welfare_tot=zeros(D,X)
d_coveredd=zeros(D,X)


for x=1:X
 for d=1:D
    d_coveredd[d,x]=value(demand_out[d,x])
    D_welfare_tot[d,x]=d_coveredd[d,x]*(D_bid_price_X[d,x] - market_price_out[1,x])
 end
end


S_production_out=zeros(S,X)


for x=1:X
for s=1:S
    S_production_out[s,x]=value(S_prod_out[s,x])
    S_profit_tot[s,x]=S_production_out[s,x]*(market_price_out[1,x]-S_cost_out[s])
    #println(GEN_S[s], ": ", @sprintf("%.2f" , S_production_out[s,x]), " MWh - Production Cost: ", @sprintf("%.2f" , S_cost_out[s]), " €/MWh", " - Profit ", GEN_S[s], ": ", @sprintf("%.2f" , S_profit_out[s,x]), " €"  )
end
end

O_production_out=zeros(O,X)

for x=1:X
for o=1:O
    O_production_out[o,x]=value(O_prod_out[o,x])
    O_profit_tot[o,x]=O_production_out[o,x]*(market_price_out[1,x]-O_cost_X[o,x])
    #println(GEN_O[o], ": ", @sprintf("%.2f" , O_production_out[o,x]), " MWh - Production Cost: ", @sprintf("%.2f" , O_cost_out[o,x]), " €/MWh", " - Profit ", GEN_O[o], ": ", @sprintf("%.2f" , O_profit_out[o,x]), " €" )
end
end


S_profit_IN=zeros(S,Y)
O_profit_IN=zeros(O,Y)

S_profit_OUT=zeros(S,W)
O_profit_OUT=zeros(O,W)

D_welfare_IN=zeros(D,W)
D_welfare_OUT=zeros(D,W)

global ssy=1
global ssw=1

    for x=1:X
        if x in sY  
            for s=1:S
                S_profit_IN[s,ssy]=S_profit_tot[s,x]
            end
            for o=1:O
                O_profit_IN[o,ssy]=O_profit_tot[o,x]
            end
            for d=1:D
                D_welfare_IN[d,ssy]=D_welfare_tot[d,x]
            end
            global ssy=ssy+1

        else
            for s=1:S
                S_profit_OUT[s,ssw]=S_profit_tot[s,x]
            end
            for o=1:O
                O_profit_OUT[o,ssw]=O_profit_tot[o,x]
            end
            for d=1:D
                D_welfare_OUT[d,ssw]=D_welfare_tot[d,x]
            end
            global ssw=ssw+1
        end
    end


# in profit average

    S_profit_IN_AVG=zeros(S,Y)

    for s=1:S
    S_profit_IN_AVG[s]=sum(S_profit_IN[s,y] for y=1:Y)/Y
    end

    O_profit_IN_AVG=zeros(O,Y)

    for o=1:O
    O_profit_IN_AVG[o]=sum(O_profit_IN[o,y] for y=1:Y)/Y
    end

    D_welfare_IN_AVG=zeros(D)


    for d=1:D
    D_welfare_IN_AVG[d]=sum(D_welfare_IN[d,y] for y=1:Y)/Y
    end

# out profit average

    S_profit_OUT_AVG=zeros(S)

    for s=1:S
    S_profit_OUT_AVG[s]=sum(S_profit_OUT[s,w] for w=1:W)/W
    end

    O_profit_OUT_AVG=zeros(O)

    for o=1:O
    O_profit_OUT_AVG[o]=sum(O_profit_OUT[o,w] for w=1:W)/W
    end

    D_welfare_OUT_AVG=zeros(D)

    for d=1:D
        D_welfare_OUT_AVG[d]=sum(D_welfare_OUT[d,w] for w=1:W)/W
    end


    for s=1:S
        println("Average profit in-sample ", GEN_S[s], @sprintf(": %.2f" , S_profit_IN_AVG[s]))
        println("Average profit out-sample ", GEN_S[s], @sprintf(": %.2f" , S_profit_OUT_AVG[s]))
    end

println("\n")
    for o=1:O
        println("Average profit in-sample ", GEN_O[o], @sprintf(": %.2f" , O_profit_IN_AVG[o]))
        println("Average profit out-sample ", GEN_O[o], @sprintf(": %.2f" , O_profit_OUT_AVG[o]))
    end

    println("\n")
    for d=1:D
        println("Average demand welfare in-sample ", DEMAND[d], @sprintf(": %.2f" , D_welfare_IN_AVG[d]))
        println("Average demand welfare out-sample ", DEMAND[d], @sprintf(": %.2f" , D_welfare_OUT_AVG[d]))
    end

        Social_Welfare_IN_AVG= sum(D_welfare_IN_AVG[d] for d=1:D) + sum(S_profit_IN_AVG[s] for s=1:S) + sum(O_profit_IN_AVG[o] for o=1:O)
        Social_Welfare_OUT_AVG= sum(D_welfare_OUT_AVG[d] for d=1:D) + sum(S_profit_OUT_AVG[s] for s=1:S) + sum(O_profit_OUT_AVG[o] for o=1:O)

        println("\n")
        println("Average social welfare in-sample:",  @sprintf(" : %.2f" , Social_Welfare_IN_AVG))
        println("Average social welfare out-sample:",  @sprintf(" : %.2f" , Social_Welfare_OUT_AVG))



        # Print number of variables and constraints
println("\n")
println("Number of variables: ", JuMP.num_variables(TWO_FOUR))
println("Number of constraints: ", JuMP.num_constraints(TWO_FOUR, count_variable_in_set_constraints=false))


# Print computational time
println("Computational time: ", end_time - start_time)

