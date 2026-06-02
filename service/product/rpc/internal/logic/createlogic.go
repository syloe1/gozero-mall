package logic

import (
	"context"
	"mall/service/product/model"

	"mall/service/product/rpc/internal/svc"
	"mall/service/product/rpc/types/product"

	"github.com/zeromicro/go-zero/core/logx"
	"google.golang.org/grpc/status"
)

type CreateLogic struct {
	ctx    context.Context
	svcCtx *svc.ServiceContext
	logx.Logger
}

func NewCreateLogic(ctx context.Context, svcCtx *svc.ServiceContext) *CreateLogic {
	return &CreateLogic{
		ctx:    ctx,
		svcCtx: svcCtx,
		Logger: logx.WithContext(ctx),
	}
}

func (l *CreateLogic) Create(in *product.CreateRequest) (*product.CreateResponse, error) {
	// 1. 前置参数校验：禁止负数
	if in.Stock < 0 || in.Amount < 0 || in.Status < 0 {
		return nil, status.Error(400, "库存、金额、状态不能为负数")
	}

	newProduct := model.Product{
		Name:   in.Name,
		Desc:   in.Desc,
		Stock:  uint64(in.Stock),
		Amount: uint64(in.Amount),
		Status: uint64(in.Status),
	}

	// 2. 插入数据
	res, err := l.svcCtx.ProductModel.Insert(l.ctx, &newProduct)
	if err != nil {
		return nil, status.Error(500, "创建产品失败，请稍后重试")
	}

	// 3. 获取自增ID
	lastID, err := res.LastInsertId()
	if err != nil {
		return nil, status.Error(500, "获取产品ID失败")
	}

	// 可选：判断ID非负（双重兜底）
	if lastID < 0 {
		return nil, status.Error(500, "无效产品ID")
	}

	// 直接转换返回，省略中间赋值
	return &product.CreateResponse{
		Id: lastID,
	}, nil
}
